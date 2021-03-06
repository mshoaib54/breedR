% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/checks.R
\name{check_var.ini}
\alias{check_var.ini}
\title{Check initial variances specification}
\usage{
check_var.ini(x, random, response)
}
\arguments{
\item{x}{list. user specification of var.ini (or NULL)}

\item{random}{formula. user specification of random effects.}

\item{response}{numeric vector or matrix.}
}
\value{
A list with initial covariance matrices for all random effects in the
  model. A logical attribute `var.ini.default` is TRUE if values were set by
  default.

matrix of observation values.
}
\description{
If the user specified initial values, verify that all random effects were
included. Otherwise, set default values. In any case, validate all initial
values.
}
