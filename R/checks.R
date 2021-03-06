## Functions for checking model components
## Internal - not exported


#' Check initial variances specification
#' 
#' If the user specified initial values, verify that all random effects were
#' included. Otherwise, set default values. In any case, validate all initial
#' values.
#' 
#' @return A list with initial covariance matrices for all random effects in the
#'   model. A logical attribute `var.ini.default` is TRUE if values were set by
#'   default.
#' 
#' @param x list. user specification of var.ini (or NULL)
#' @param random formula. user specification of random effects.
#' @param response numeric vector or matrix.
#' @return  matrix of observation values.
check_var.ini <- function (x, random, response) {
  
  
  ## terms in the random component + 'residual'
  random.terms <- switch( is.null(random) + 1,
                          c(attr(stats::terms(random), 'term.labels'), 'residuals'),
                          'residuals')
  
  if (!is.null(x)) {
    
    ## set flag: initial variances not specified by user
    attr(x, 'var.ini.default') <- FALSE
    
    ## normalize names
    names(x) <- match.arg(names(x),
                          random.terms,
                          several.ok = TRUE)
    
    ## check that all the required variances are given
    if (!setequal(names(x), random.terms)) {
      stop(paste('Some initial variances missing in var.ini.\n',
                 'Please specify either all or none.'))
    }
  } else {
    
    ## set default values and flag
    div_fun <- breedR.getOption('default.initial.variance')
    default_ini <- 
      eval(div_fun)(response, dim = 1, cor.effect = 0.1, digits = 2)
    x <- lapply(random.terms, function(x) default_ini)
    names(x) <- random.terms
    attr(x, 'var.ini.default') <- TRUE
  }
  
  ## validate values
  for (i in seq_along(x)) {
    validate_variance(x[[i]], what = names(x)[i], where = "var.ini specification")
  }
  
  ## return component with names normalised and 
  ## possibly default values added
  return(x)
}


## Checks and completes the specification of a genetic model
check_genetic <- function(model = c('add_animal', 'competition'),
                          pedigree,
                          id,
                          coordinates,
                          competition_decay = 1,
                          pec = FALSE,
                          autofill = TRUE,
                          var.ini,
                          data,
                          response,
                          ...) {
  
  ## do not include data in the call
  ## data is an auxiliar for checking and substituting id
  ## but it is not part of the genetic component specification
  mc <- match.call()
  mc <- mc[!names(mc) %in% c('data', 'response')]
  
  ## Mandatory arguments
  for (arg in c('model', 'pedigree', 'id')) {
    if (eval(call('missing', as.name(arg))) || 
        eval(call('is.null', as.name(arg))))
      stop(paste('Argument', arg, 'required in the genetic component.'))
  }
  
  ## Match argument model
  mc$model <- match.arg(model)
  
  ## Check type of argument pedigree 
  ## recode if necessary and always return a 'pedigree'
  if (!inherits(pedigree, 'pedigree')){
    ped.df <- try(as.data.frame(pedigree))
    if (inherits(ped.df, 'try-error')) 
      stop(paste('The argument pedigree in the genetic component',
                 'must be coercible to data.frame'))
    if (!ncol(ped.df) == 3)
      stop(paste('The argument pedigree in the genetic component',
                 'must have exactly 3 columns\ncorresponding to the',
                 'individual, its father and its mother respectively.'))
    pedigree <- build_pedigree(1:3, data = ped.df)
  }
  if (!all(check_pedigree(pedigree))) {
    pedigree <- build_pedigree(1:3, data = as.data.frame(pedigree))
  }
  mc$pedigree <- eval(pedigree, parent.frame())
  
  
  ## id must be either a variable name in data
  ## or a vector of codes in the pedigree
  if (length(id) == 1) {
    if (is.character(id) && id %in% names(data))
      mc$id <- as.integer(data[, id])
    else
      stop(paste('The argument id in the genetic component',
                 'must be either a vector of codes or a variable',
                 'name in the argument data.'))
  } else {
    mc$id <- id
  }

  ## The codes in id must correspond to valid codes in the pedigree
  ## possibly recoded
  if (!is.null(attr(mc$pedigree, "map")))
    recoded_id <- attr(mc$pedigree, "map")[mc$id]
  else recoded_id <- mc$id
  if (!all(idx <- recoded_id %in% mc$pedigree@label))
    stop(paste('The following individuals in id are',
               'not represented in the pedigree:\n',
               toString(mc$id[which(!idx)])))

  ## flag indicating whether the var.ini was taken by default
  ## or specified by the user
  attr(mc, 'var.ini.default') <- FALSE

  ## default initial variance function
  div_fun <- breedR.getOption('default.initial.variance')
  
  ## dimension of the genetic effect
  dim <- switch(mc$model, add_animal = 1, competition = 2)
  
  ## Set default var.ini if missing
  if (missing(var.ini) || is.null(var.ini)) {

    ## default initial covariance matrix
    var.ini <- 
      eval(div_fun)(response, dim = dim, cor.effect = 0.1, digits = 2)
    
    ## set flag indicating a default initial value
    attr(mc, 'var.ini.default') <- TRUE
  }
  
  ## Validate initial variance (SPD, dimensions, etc.)
  validate_variance(
    var.ini,
    dimension = rep(dim*ncol(as.matrix(response)), 2),
    where = 'genetic component.')
  
  ## Checks specific to competition models
  if (mc$model == 'competition') {
    
    ## Mandatory arguments
    for (arg in c('coordinates')) {
      if (eval(call('missing', as.name(arg))))
        stop(paste('Argument', arg, 'required in the genetic component.'))
    }
    
    mc$coordinates <- normalise_coordinates(coordinates,
                                            where = 'genetic component')
    
    ## Check pec argument
    # Specification of Permanent Environmental Effect
    ## Must be a list or a logical
    ## in the latter case, make it a list
    if (!is.list(pec)) {
      if (length(pec) == 1) {
        if (is.logical(pec)) {
          pec <- list(present = pec)
        } else {
          if (is.numeric(pec) && pec > 0) {
            pec <- list(present = TRUE, var.ini = pec)
          } else {
            stop('pec must be either list, a logical value or a positive number')
          }
        }
      } else {
        stop('pec must be either a list, a logical value or a positive number')
      }
    }
    
    ## Must be named
    if (is.null(names(pec)) || !all(nchar(names(pec))>0))
      stop('pec must be a named list')
    
    ## Match names
    names(pec) <- match.arg(names(pec), c('present', 'var.ini'), several.ok = TRUE)
    
    ## If there is no specification of 'present' it means it is present
    if (!'present' %in% names(pec)) {
      pec$present <- TRUE
    }
    
    ## Default initial variance
    if (!'var.ini' %in% names(pec)) {
      if (!attr(mc, 'var.ini.default') && pec$present) {
        stop(paste0('var.ini must be specified for pec as well, ',
                    'in the competition specification.\n',
                    'e.g. pec = list(present = TRUE, var.ini = 1)'))
      }
      
      ## default initial covariance matrix
      pec$var.ini <-
        eval(div_fun)(response, dim = 1, cor.effect = 0.1, digits = 2)
    }
    
    ## Validate initial variance in pec
    validate_variance(pec$var.ini,
                      what = "pec$var.ini",
                      where = "genetic component")
    
    ## At this point, names should match exactly those
    if (!all(idx <- names(pec) %in% c('present', 'var.ini'))) {
      bad.args <- names(pec)[!idx]
      stop(paste0('Unrecognized argument',
                  ifelse(length(bad.args) == 1, '', 's'), ' ',
                  paste(bad.args, collapse = ', '), ' in pec'))
    }
    if (!is.logical(pec$present) | length(pec$present) != 1)
      stop('one logical value expected in pec$present')
    mc$pec <- pec
    
    ## TODO: check here whether none or all var.ini were specified
    ## and return var.ini.default as an attribute
    
    ## If missing, assume the default value
    stopifnot(is.numeric(competition_decay))
    stopifnot(competition_decay > 0)
    mc$competition_decay <- competition_decay
  }
  
  mc$var.ini <- var.ini
  mc$autofill <- autofill
  
  return(structure(as.list(mc[-1]),
                   var.ini.default = attr(mc, 'var.ini.default')))
}



check_spatial <- function(model = c('splines', 'AR', 'blocks'),
                          coordinates,
                          id,
                          n.knots,
                          rho,
                          autofill = TRUE,
                          sparse   = TRUE,
                          var.ini,
                          data,
                          response) {

  ## do not include data in the call
  ## data is an auxiliar for checking and substituting id
  ## but it is not part of the genetic component specification
  mc <- match.call()
  mc <- mc[!names(mc) %in% c('data', 'response')]
  
  for (arg in c('model', 'coordinates')) {
    if (eval(call('missing', as.name(arg))))
      stop(paste('Argument', arg, 'required in the spatial component.'))
  }
  
  mc$model <- match.arg(model)
  
  mc$coordinates <- normalise_coordinates(coordinates, 'spatial component')
  
  ## If blocks model, include the values of the relevant covariate
  if (model == "blocks") {
    
    ## id must be either a variable name in data
    ## or a vector of codes in the pedigree
    if (length(id) == 1) {
      if (is.character(id) && id %in% names(data))
        mc$id <- as.integer(data[, id])
      else
        stop(paste('The argument id in the block component',
                   'must be either a vector of codes or a variable',
                   'name in the argument data.'))
    }
    mc$id <- eval(mc$id)
    
    # Only factors make sense for blocks
    # If it is already a factor, it may have
    # unobserved levels. Otherwise, make it a factor.
    if( !is.factor(mc$id) )
      mc$id <- as.factor(mc$id)
    
  }
  
  ## checks for splines models
  if (mc$model == 'splines') {
    if (!missing(n.knots)) {
      ## If n.knots specified, check consistency
      if (!is.vector(n.knots) || length(n.knots) !=2 || !all(n.knots%%1==0))
        stop(paste('n.knots must be a vector of two integers'))
      mc$n.knots <- n.knots
    }
  }
  
  ## checks for AR models
  if (model == 'AR'){
    
    ## rho not specified: make it NA in both dimensions
    if (missing(rho) || is.null(rho)) rho <- matrix(c(NA, NA), 1, 2)
    
    if (any(is.na(rho))) {
      ## any NA: build grid
      rho.grid <- build.AR.rho.grid(rho)
    } else {
      ## fully specified: keep it as is
      ## can be a grid, or a vector
      rho.grid <- rho
    }
    

    check_rho_values <- function(rho) {
     if (!all(vapply(rho, is.numeric, TRUE)))
      stop('Argument rho in the spatial component must be numeric')
      if (any(abs(rho)>=1))
        stop('rho must contain numbers strictly between -1 and 1')
      if (!is.vector(rho))
        stop('rho must be a vector')
      if (length(rho)!=2)
        stop('rho must contain exactly two components')
      
      return(invisible(TRUE))
    }
    
    if (is.null(nrow(rho.grid))) {
      ## i.e. if is not really a grid
      check_rho_values(rho.grid)
    } else {
      ## grid case
      apply(rho.grid, 1, check_rho_values)
    }
    
    mc$rho <- rho.grid
  }
  
  ## flag indicating whether the var.ini was taken by default
  ## or specified by the user
  attr(mc, 'var.ini.default') <- FALSE
  
  ## default initial variance function
  div_fun <- breedR.getOption('default.initial.variance')

  ## dimension of the spatial effect
  dim <- 1
  
  if (missing(var.ini) || is.null(var.ini)) {
    
    ## default initial covariance matrix
    var.ini <- eval(div_fun)(response, dim, cor.effect = 0.1, digits = 2)
    
    ## set flag indicating a default initial value
    attr(mc, 'var.ini.default') <- TRUE
  } 

  ## Validate initial variance (SPD, dimensions, etc.)
  validate_variance(
    var.ini,
    dimension = rep(dim*ncol(as.matrix(response)), 2),
    where = 'spatial component.'
  )
  mc$var.ini <- var.ini
  
  ## evaluate remaining parameters
  mc$autofill <- autofill
  mc$sparse   <- sparse
  
  return(structure(as.list(mc[-1]),
                   var.ini.default = attr(mc, 'var.ini.default')))
}



check_generic <- function(x, response){
  
  mc <- match.call()
  
  if (missing(x)) return(NULL)
  
  ## check general specification
  if (!is.list(x) || is.null(names(x)))
    stop('The generic component must be a named list.', call. = FALSE)
  if (!all(nchar(names(x))>0))
    stop('All elements of the generic component must be named.', call. = FALSE)
  if (any(duplicated(names(x))))
    stop('Duplicated names in generic elements.', call. = FALSE)
  if (!all(idx <- sapply(x,is.list))) {
    nm <- names(x)[!idx]
    if (length(nm) > 1)
      msg <- paste("Elements", paste(nm, collapse = ", "),
                   "of the generic component must be lists.")
    else
      msg <- paste("Element", paste(nm, collapse = ", "),
                   "of the generic component must be a list.")
    stop(msg, call. = FALSE)
  }
  
  ## validate individual elements
  for (arg.idx in seq_along(x)){ 
    id <- paste("generic component", names(x)[arg.idx])
    result <- do.call(
      'validate_generic_element', 
      c(x[[arg.idx]],
        response = list(response),
        where = id)
    )
    ## If valid, the original spec might have been completed
    ## with a default initial variance
    x[[arg.idx]] <- result
  }
  
  ## Check default var.ini values
  ## Either all specified or all by default
  var.ini.default <- vapply(x, attr, TRUE, 'var.ini.default')
  if (any(var.ini.default) && any(!var.ini.default)) {
    stop(paste('Some initial variances missing in the generic component.\n',
               'Please specify either all or none.'), call. = FALSE)
  }
  
  ## Merge individual attributes into the list object
  for (i in seq_along(x)) attr(x[[i]], 'var.ini.default') <- NULL
  attr(x, 'var.ini.default') <- any(var.ini.default)
  
  return(x)
}


validate_generic_element <- function(incidence, 
                                     covariance, 
                                     precision, 
                                     var.ini, 
                                     response,
                                     where) {
  
  mc <- match.call()
  mc <- mc[names(mc) != 'response' & names(mc) != 'where']
  
  for (arg in c('incidence')) {
    if (eval(call('missing', as.name(arg))))
      stop(paste('Argument', arg, 'required in the', where), call. = FALSE)
  }
  if (!xor(missing(covariance), missing(precision)))
    stop(paste('Exactly one argument between covariance',
               'and precision must be specified in the', where), call. = FALSE)
  
  if (missing(covariance)) {
    structure <- precision
    str.name <- 'precision'
  }
  else {
    structure <- covariance
    str.name <- 'covariance'
  }
  if(!is.matrix(incidence) && !inherits(incidence, 'Matrix'))
    stop(paste('Argument incidence must be of type matrix in the', where),
         call. = FALSE)
  if(!is.matrix(structure) && !inherits(structure, 'Matrix'))
    stop(paste(str.name, 'must be of type matrix in the', where), call. = FALSE)
  if(ncol(incidence) != nrow(structure))
    stop(paste('Non conformant incidence and', str.name, 'matrices in the', where),
         call. = FALSE)

  ## flag indicating whether the var.ini was taken by default
  ## or specified by the user
  attr(mc, 'var.ini.default') <- FALSE
  
  ## default initial variance function
  div_fun <- breedR.getOption('default.initial.variance')
  
  ## dimension of the generic effect
  dim <- 1
  
  if (missing(var.ini) || is.null(var.ini)) {
    ## If not specified, return function that gives the value
    ## in order to check later whether the value is default or specified
    var.ini <- eval(div_fun)(response, dim, cor.effect = 0.1, digits = 2)
    
    ## set flag indicating a default initial value
    attr(mc, 'var.ini.default') <- TRUE
  }
  
  ## Validate initial variance 
  ## even if default: the user could have changed the default function
  validate_variance(
    var.ini,
    dimension = rep(dim*ncol(as.matrix(response)), 2),
    where = where)
  
  mc$var.ini <- var.ini
  
  return(structure(as.list(mc[-1]),
                   var.ini.default = attr(mc, 'var.ini.default')))
}


#' Normalise coordinates specification
#' 
#' If checks succeed, returns a complete normalised specification.
#' 
#' @param x matrix-like object to be checked
#' @param where string. Model component where coordinates were specified. For 
#'   error messages only. E.g. \code{where = 'genetic component'}.
#'   
#' @return a two-column data.frame, with numeric values.
normalise_coordinates <- function (x, where = '') {

    ## Check coordinates and cast to data.frame
  coord <- try(as.data.frame(x))
  if (inherits(coord, 'try-error') || !is.data.frame(coord))
    stop(paste('Argument coordinates in the', where,
              'not coercible to a data.frame'))

  ## Recast to data.frame. If nrow(coord) == 1, vapply returns
  ## a named vector, not a data.frame. E.g.:
  ## is.data.frame(vapply(data.frame(x=1, y=2), as.numeric, rep(1, 1)))
  coord <- try(as.data.frame(vapply(coord,
                                    as.numeric,
                                    rep(1, nrow(coord)))))
  
  if (inherits(coord, 'try-error'))
    stop(paste('Argument coordinates in the', where, 'not numeric'))
  if (ncol(coord) != 2)
    stop(paste('Only two dimensions admitted for coordinates',
               'in the', where))
  return(coord)
}


#' Check properties for a covariance matrix
#'
#' @param x number or matrix.
#' @param dimension numeric vector with dimensions of the matrix
#' @param what string. What are we validating
#' @param where string. Model component where coordinates were specified. For 
#'   error messages only. E.g. \code{where = 'competition specification'}.
#'
#' @return \code{TRUE} if all checks pass
validate_variance <- function (x, dimension = dim(as.matrix(x)),
                               what = 'var.ini', where = '') {

  stopifnot(
    is.numeric(x <- as.matrix(x)),
    is.numeric(dimension),
    length(dimension) == 2
  )
  
  if (nrow(x)!=ncol(x))
    stop(paste(what, "must be a square matrix in the", where), call. = FALSE)
  if (length(x) != prod(dimension))
    stop(paste(what, "must be a", paste(dimension, collapse = 'x'),
               "matrix in the", where), call. = FALSE)
  ev <- eigen(x, symmetric = TRUE, only.values = TRUE)$values
  if (!isSymmetric(x, check.attributes = FALSE) || !all( ev > 0 ))
    stop(paste(what, "must be a SPD matrix in the", where), call. = FALSE)
  
  return(TRUE)
}
