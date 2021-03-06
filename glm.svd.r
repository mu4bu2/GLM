#' Fitting Generalized Linear Models
#'
#' Similar to \code{glm.fit} but uses the SVD to detect ill-conditioned
#' problems and conducts IRWLS in projected subspace for efficiency.
#'
#' @param X an n by p real-valued dense model matrix
#' @param y a response vector of length n
#' @param family a family function or the result of a call to a family function
#' @param maxit integer number of maximum number of IRWLS iterations
#' @param tol IRWLS positive convergence tolerance
#' @param stol positive numerical condition tolerance
#' @param singular.ok if FALSE a numerically-singular fit stops with error
#' @param weights vector of observation weights
#' @param reg.method indicates regularization approach: 'column projection' follows R's GLM approach; 'minimum norm' finds the LS solution of minimal norm.
#' @param LAPACK if FALSE use R's column-ordered subset selection when \code{reg.method == 'column projection'} otherwise use default LAPACK pivots.
#' @return A list with model coefficients b, number if IRWLS iterations, and column pivoting indices.
#' Returns a list with entries:
#' \describe{
#'   \item{b:}{ model coefficients}
#'   \item{iterations:}{ number of IRWLS iterations}
#'   \item{rank:}{ rank of model matrix}
#'   \item{pivot:}{ model matrix column pivot}
#' }
#' @seealso \code{\link{glm.fit}}
glm.svd =
function(X, y, family=binomial, maxit=25, tol=1e-10, stol=1e-10,
         singular.ok=TRUE, weights,
         reg.method=c("column projection", "minimum norm"),
         LAPACK=FALSE)
{
  singular = ifelse(singular.ok, warning, stop)
  reg.method = match.arg(reg.method)
  if(is.list(X)) S = X
  else S = svd(X)
  V = S$v
  nvars = NCOL(S$u)
  idx = seq(nvars)
  i = (S$d / S$d[1]) > stol
  k = sum(i)
  pivot = seq(nvars)
  if (k < nvars)
  {
    singular("Singular system detected of rank: ", k, " using threshold: ", stol)
    if(reg.method == "column projection")
    {
      Q = qr(t(S$v[, 1:k]), LAPACK=LAPACK) # Golub SVD subsel heuristic
      # when LAPACK=FALSE uses R's custom pivoting strategy
      pivot = Q$pivot
      idx = sort(head(pivot, k))
      omit = tail(Q$pivot, nvars - k)
# XXX we can maybe instead use a slightly cheaper downdating svd scheme here:
      S_new = svd(X[, -omit])
#     double-check that this worked (it may not have), if not resort to
#     something else... XXX can this be improved?
      if((tail(S_new$d, 1) / S_new$d[1]) <= stol)
      {
        warning("Whoops! SVD subset selection failed, trying dqrdc2 on full matrix")
        if(is.list(X)) Q = qr(X$u %*% (X$d * t(X$v)), LAPACK=FALSE)
        else Q = qr(X, LAPACK=FALSE)
        pivot = Q$pivot
        idx = sort(head(pivot, k))
        omit = tail(Q$pivot, nvars - k)
        S_new = svd(X[, -omit])
      }
      S = S_new
      message("omittig column(s) ", paste(omit, collapse=","))
    }
  }

  s = rep(0, ncol(S$u))
  if(!is(family, "family")) family = family()
  nobs = NROW(y)    # needed by the initialize expression below
  nvars = NCOL(S$u) # ditto
  if(missing(weights)) weights = rep(1, nobs)
  variance = family$variance
  linkinv = family$linkinv
  mu.eta = family$mu.eta
  etastart = NULL
  eval(family$initialize)
  eta = family$linkfun(mustart)
  dev.resids = family$dev.resids
  dev = sum(dev.resids(y, linkinv(eta), weights))
  devold = 0
  for(j in 1:maxit)
  {
    g      = linkinv(eta)
    varg   = variance(g)
    if(any(is.na(varg))) stop("NAs in variance of the inverse link function")
    if(any(varg==0)) stop("Zero value in variance of the inverse link function")
    gprime  = mu.eta(eta)
    if(any(is.na(gprime))) stop("NAs in the inverse link function derivative")
    z = eta + (y - g) / gprime
    W = weights * as.vector(gprime^2 / varg)
    # The following is as well-conditioned as W is
    C   = chol(crossprod(S$u, W*S$u), pivot=TRUE)
    piv = attr(C, "pivot")
    s   = forwardsolve(t(C), crossprod(S$u, W*z)[piv])
    s   = backsolve(C, s)[order(piv)]
    eta   = drop(S$u %*% s)
    dev = sum(dev.resids(y, g, weights))
    if(abs(dev - devold) / (0.1 + abs(dev)) < tol) break
    devold = dev
# R essentially computes this (via dqrdc2.f)
##  Q = qr(W * X)
##  omit = tail(Q$pivot, ncol(X) - Q$rank)
##  now omit columns and solve...
##  fit = qr.solve(W * X, W * z)
##  eta = drop(x %*% fit)
##  g = linkinv(eta)
  }
  x = rep(NA, NCOL(X))
  inv = 1/S$d
  if(reg.method == "minimum norm") inv[inv > 1/stol] = 1
  x[idx] = drop(S$v %*% (s*inv))
  list(coefficients=x,iterations=j, rank=k, pivot=pivot)
}
