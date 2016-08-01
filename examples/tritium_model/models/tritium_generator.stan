/* Tritium Spectrum Model (Generator)
* -----------------------------------------------------
* Copyright: J. A. Formaggio <josephf@mit.edu>
*
* Date: 25 September 2014
* Modified: Feb 17 2016 by MG
*
* Purpose:
*
*		Program will generate a set of sampled data distributed according to the beta decay spectrum of tritium.
*		Program assumes Project-8 measurement (frequency) and molecular tritium as the source.
*		Spectrum includes simplified beta-function with final state distribution (assuming 0.36 eV gaussian model)
*		Includes broadening due to magnetic field homogeneity, radiative energy loss, Doppler and scattering.
*		T_2 scattering cross-section model implemented.
*		Note that sample events are distributed according to true distribution.
*
*
* Collaboration:  Project 8
*/

functions{

  // Load libraries

  include<-constants;
  include<-func_routines;
  include<-Q_Functions;
  include<-neutrino_mass_functions;
  include<-tritium_functions;

}



data {

  //Mass ordering:
  //if MassHierarchy = 1, normal hierarchy (delta_m31>0)
  //if MassHierarchy = -1, inverted hierarchy (delta_m31<0)
  int MassHierarchy;

  real lightest_neutrino_mass;

  //   Primary magnetic field (in Tesla)

  real<lower=0> BField;
  real BFieldError_fluct;

  //   Range for fits (in eV)
  real<lower=0 > minKE;
  real<lower=minKE> maxKE;

  //  Cross-section of e-T2 , in meter^-2

  vector[2] xsec_avekin;
  vector[2] xsec_bindkin;
  vector[2] xsec_msq;
  vector[2] xsec_Q;
  real xsection_set; //set from Devyn's thesis : xsec = 4.4e-18 cm^2 @ 17 keV

  //  Conditions of the experiment and measurement

  real number_density;			//  Tritium number density (in meter^-3)
  real effective_volume;		        //  Effective volume (in meter^3)
  real measuring_time;			//  Measuring time (in seconds)

  //  Background rate

  real background_rate_mean;			//  Background rate in Hz/eV

  //  Clock and filter information

  real fBandpass;
  real fBandpassMin;
  real fclockError;
  // int  fFilterN;
  // real fclock;

  // Endpoint model input from feature/MH_Talia (Q_generator.stan)

  real T_set;      //Average temperature of source gas in Kelvin
  real deltaT_fluctuation;    //Temperature uncertainty due to fluctuations (K)
  real deltaT_rot;    //Temperature uncertainty due to unaccounted for higher rotational states (K)

  int num_J;     // Number of rotational states to be considered (10)
  real lambda_set;    //Average fraction of T2 component of source in ortho (odd rotation) state
  real delta_lambda; //Uncertainty in (lambda = sum(odd-rotation-state-coefficients))

  int num_iso;    //Number of isotopologs under consideration
  vector[num_iso] Q_T_molecule_set;          // Best-estimate endpoint values for tritium molecule (T2, HT, DT)
  real Q_T_atom_set;          // Best-estimate endpoint values for atomic tritium

  real epsilon_set;   // Average fractional activity of source gas compared to pure T_2
  real kappa_set;     // Average ratio of HT to DT
  real eta_set;       // Average proportion of atomic tritium

}


transformed data {

  real s12;
  real s13;
  real m1;
  real m2;
  real m3;
  real dm21;
  real dm31;
  real dm32;
  vector[nFamily()] m_nu;
  vector[nFamily()] U_PMNS;


  real minFreq;
  real maxFreq;
  real fclock;

  simplex[num_iso] composition; //Composition of the gas

  vector<lower=0.0>[num_iso] mass_s; //mass of tritium species

  if (MassHierarchy == 1){
    m_nu <- MH_masses(lightest_neutrino_mass, meas_delta_m21(), meas_delta_m32_NH(), MassHierarchy);
    s13 <- meas_sin2_th13_NH();
  }  else {
    m_nu <- MH_masses(lightest_neutrino_mass, meas_delta_m21(), meas_delta_m32_IH(), MassHierarchy);
    s13 <- meas_sin2_th13_IH();
  }
  s12 <- meas_sin2_th12();
  U_PMNS <- get_U_PMNS(nFamily(),s12,s13);


  minFreq <- get_frequency(maxKE, BField);
  maxFreq <- get_frequency(minKE, BField);

  fclock <- 0.;

  // if (fBandpass > (maxFreq-minFreq)) {
  //   print("Bandpass filter (",fBandpass,") is greater than energy range (",maxFreq-minFreq,").");
  //   print("Consider enlarging energy region.");
  // }

  //Transformed Data from feature/MH_Talia (Q_generator.stan)
  // Setting the masses of the tritium species

  mass_s[1] <- tritium_atomic_mass();
  mass_s[2] <- hydrogen_atomic_mass();
  mass_s[3] <- deuterium_atomic_mass();


  composition <- find_composition(epsilon_set,kappa_set);

}

parameters {

  //Parameters used for the convergence of the distributions
  real uB;
  real uQ1;
  real uQ2;
  real uF;
  real uT;

  //Physical parameters
  real<lower=0.0> eDop;
  real<lower=0.0> duration;
  real<lower=minKE,upper=maxKE> KE_data;

  real<lower=0.0, upper=1.0> lambda;
  real<lower=minKE, upper=maxKE> Q;
}

transformed parameters{

  //Neutrino mass
  real<lower=0> neutrino_mass;
  //Magnetic field
  real<lower=0> MainField;
  //Cross-section calculations
  real beta;
  real xsec;
  real<lower=0> scatt_width;
  real rad_width;
  real tot_width;
  real sigma_freq;
  // Molecular stuff from Talia
  real<lower=0.0> sigmaT;     // Total temperature variation (K)
  real<lower=0.0> temperature;   // Temperature of source gas (K)

  real df;
  real frequency;

  real freq_recon;
  real kDoppler;
  real KE_shift;

  real activity;
  real signal_fraction;
  real norm_spectrum;
  real spectrum_shape;
  real spectrum;

  // Q_generator from feature/MH_Talia


  real<lower=0.0> p_squared;         // (Electron momentum)^2 at the endpoint
  vector<lower=0.0>[num_iso] sigma_0;
  real<lower=0> Q_mol;
  real<lower=0> sigma_mol;
  real<lower=0> sigma_atom;
  real<lower=0> Q_mol_random;
  real<lower=0> Q_atom_random;


  real sigma_theory;

  // Determine effective mass to use from neutrino mass matrix

  neutrino_mass <- get_effective_mass(U_PMNS, m_nu);

  // Obtain magnetic field (with prior distribution)
  MainField <- BField + vnormal_lp(uB, 0. , BFieldError_fluct);

  // Temperature of system
  sigmaT <- deltaT_fluctuation;
  temperature <- T_set + vnormal_lp(uT, 0. , sigmaT);

  // Calculate scattering length, radiation width, and total width;
  //The total cross-section is equal to the cross-section of each species, weighted by their relative composition
  // Here we are considering that the ionization cross-section for each molecular tritium {HT, DT, TT} is the same.
  beta <- get_velocity(KE_data);
  // print(KE_data);
  // xsec <- 0.; //initialize cross section
  // xsec <- xsec + (1-eta_set) * xsection(KE,  xsec_avekin[1], xsec_bindkin[1], xsec_msq[1], xsec_Q[1]);//adding the cross-section with modelucar tritium
  // xsec <- xsec + (eta_set) * xsection(KE,  xsec_avekin[2], xsec_bindkin[2], xsec_msq[2], xsec_Q[2]);//adding the cross-section with atomic tritium
  xsec <- xsection_set; //cross section set in Devyn's thesis
  scatt_width <- number_density * c() * beta * xsec;

  rad_width <- cyclotron_rad(MainField);
  tot_width <- (scatt_width + rad_width);
  sigma_freq <- (scatt_width + rad_width) / (4. * pi());//LOOK!

  // Find standard deviation of endpoint distribution (eV), given normally distributed input parameters.

  for (i in 1:num_iso) {
    p_squared <- 2.0 * Q_T_molecule_set[i] * m_electron();
    sigma_0[i] <- find_sigma(temperature, p_squared, mass_s[i], num_J, lambda); //LOOK!
  }


  //  Take averages of Q and sigma values of molecule

  Q_mol <- sum(composition .* Q_T_molecule_set);
  sigma_mol <- sqrt(sum(composition .* sigma_0 .* sigma_0)); // * (1. + sigma_theory);

  //  Find sigma of atomic tritium

  sigma_atom <- find_sigma(temperature, 2.0 * Q_T_atom_set * m_electron(), 0., 0, 0.);

  // Get a random value of the endpoint for each molecular and atomic tritium

  Q_mol_random <- vnormal_lp(uQ1, Q_mol,sigma_mol);
  Q_atom_random <- vnormal_lp(uQ2, Q_T_atom_set,sigma_atom);


  // Calculate frequency dispersion

  frequency <- get_frequency(KE_data, MainField);

  df <- vnormal_lp(uF, 0.0, sigma_freq);

  freq_recon <- frequency + df - fclock;

  // Calculate Doppler effect from tritium atom/molecule motion

  // Determine total rate from activity for the molecular tritium
  activity <-  3 * tritium_rate_per_eV() * number_density * effective_volume / (tritium_halflife() / log(2.) );
  norm_spectrum <-activity * measuring_time;
  signal_fraction <- activity/(activity + background_rate_mean);

  spectrum <- 0;
  for (i in 1:num_iso){

    kDoppler <-  m_electron() * beta * sqrt(eDop / mass_s[i]);
    KE_shift <- KE_data + kDoppler;

    // Determine signal from beta function

    spectrum_shape <- spectral_shape(KE_data, Q_mol_random, U_PMNS, m_nu);
    spectrum <- spectrum + (eta_set) * composition[i] * norm_spectrum * spectrum_shape;
  }

  // Determine signal and background rates from beta function and background level

  spectrum_shape <- spectral_shape(KE_data, Q_atom_random, U_PMNS, m_nu);
  spectrum <- spectrum + (1.-eta_set) * norm_spectrum * spectrum_shape;

  // Adding the background to the spectrum
  spectrum <- spectrum + background_rate_mean * measuring_time;

  //Filtering
  // spectrum <- spectrum *filter_log;

}

model {

  KE_data ~ uniform(minKE,maxKE);

  # Thermal Doppler broadening of the tritium source

  eDop ~ gamma(1.5,1./(k_boltzmann() * temperature));

  # Frequency broadening from collision and radiation

  duration ~ exponential(scatt_width);

  # Effect of filter in cleaning data

  // freq_recon ~ filter(0., fBandpass, fFilterN);
  // freq_recon ~ uniform(minFreq,maxFreq);

  // Set mixture of molecular and atomic tritium, if needed

  increment_log_prob(log_sum_exp(log(eta_set) + normal_log(Q, Q_mol, sigma_mol),
                                 log1m(eta_set) + normal_log(Q, Q_T_atom_set, sigma_atom)));

}

generated quantities {

  int isOK;
  real freq_data;
  real time_data;
  real spectrum_data;
  real KE_recon;

  #   Simulate duration of event and store frequency and reconstructed kinetic energy

  time_data <- duration;
  freq_data <- freq_recon;
  KE_recon <- get_kinetic_energy(frequency+df, MainField);

  # Compute the number of events that should be simulated for a given frequency/energy.  Assume Poisson distribution.

  spectrum_data <- spectrum;

  # Tag events that are below DC in analysis

  isOK <- (freq_data > 0.);

}