/*
* MC morpho testing fit
* -------------------------------------------------------------------
* Author: Mathieu Guigue <mathieu.guigue@pnnl.gov>
*
* Date: December 5th 2016
*
* Purpose:
*
* Generic and simple model for testing
*
*/
data
{
    int<lower=1> N;
    real y[N];
}
parameters
{
    real mu;
}
model
{
    y ~ normal(mu, 1);
}
