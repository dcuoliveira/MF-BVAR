library('padr')
library('lubridate')
library('zoo')

gen_Y_rho_psi = function(phi_post,
                         Yt,
                         delta_Yt,
                         t,
                         k){
  y_beta2 <- matrix(0, nrow = 1, ncol = (t-k))
  for(i in 1:(t-k)){
    aux <- 0
    aux <- phi_post[1]*Yt[(i+k-1)]
    for(j in 1:(k-1)){
      aux <-  aux + phi_post[(j+1)]*delta_Yt[(i+k-j)]
    }
    
    y_beta2[,i] <- aux
  }
  return(y_beta2)
}

gen_X_beta2 = function(phi_post,
                       Xt,
                       delta_Xt,
                       t,
                       k) {
  x_beta2 <- matrix(0, nrow = 2, ncol = (t-k))
  for(i in 1:(t-k)){
    aux <- 0
    
    aux <- phi_post[1]*Xt[,(i+k-1)]
    for(j in 1:(k-1)){
      aux <-  aux + phi_post[(j+1)]*delta_Xt[,(i+k-j)]
    }
    x_beta2[,i] <- aux
  }
  return(x_beta2)
}

gen_X_rho_xi = function(Rt,
                        delta_Rt,
                        k){
  #Creating X matrix
  x_vec <- c(Rt[k:(t-1)])
  for(i in k:2){
    aux <- delta_Rt[i:(t+1-i)]
    x_vec <- c(x_vec,aux)
  }
  return(matrix(x_vec, nrow = k, byrow = T))
}

polycreate = function(x,
                      order){
  y = 0
  for (p in 1:order){
    y = y + x^p
  }
  return(y)
}

h_epsilon_poly = function(epsilon,
                          p){
  return(polycreate(x=epsilon,
                    p=p))

}

data_frame_to_ts_list = function(df,
                                 freq_vec){
  
}

merge_fx_sneer_data = function(){
  fx_data = read.csv(here('src', 'data', 'currencies.csv')) %>% mutate(date=ymd(date)) %>% select(-X)
  
  sneer_data = read.csv(here('src', 'data', 'sneer.csv'))%>% mutate(date=ymd(date)) %>%
    pad() %>% mutate(weekday=weekdays(date, abbreviate = TRUE)) %>% filter(weekday=='Sex') %>% select(-weekday, -X)
  
  merge_data = merge(sneer_data, fx_data) 
  merge_data = na.locf(na.locf(merge_data), fromLast = TRUE)
  colnames(merge_data) = unlist(lapply(colnames(merge_data), function(x){strsplit(x, '.', fixed = TRUE)[[1]][1]}))
  rownames(merge_data) = merge_data$date
  
  return(merge_data)
}

posteriors_draws_koopetal2010 = function(data){
  # Reset random number generator for reproducibility
  set.seed(221994)
  
  # Obtain data matrices
  y <- t(data$data$Y)
  w <- t(data$data$W)
  x <- t(data$data$X)
  
  r <- data$model$rank # Set rank
  
  tt <- ncol(y) # Number of observations
  k <- nrow(y) # Number of endogenous variables
  k_w <- nrow(w) # Number of regressors in error correction term
  k_x <- nrow(x) # Number of differenced regressors and unrestrictec deterministic terms
  k_gamma <- k * k_x # Total number of non-cointegration coefficients
  
  k_alpha <- k * r # Number of elements in alpha
  k_beta <- k_w * r # Number of elements in beta
  
  # Priors
  a_mu_prior <- data$priors$noncointegration$mu # Prior means
  a_v_i_prior <- data$priors$noncointegration$v_i # Inverse of the prior covariance matrix
  
  v_i <- data$priors$cointegration$v_i
  p_tau_i <- data$priors$cointegration$p_tau_i
  
  sigma_df_prior <- data$priors$sigma$df # Prior degrees of freedom
  sigma_scale_prior <- data$priors$sigma$scale # Prior covariance matrix
  sigma_df_post <- tt + sigma_df_prior # Posterior degrees of freedom
  
  # Initial values
  beta <- matrix(0, k_w, r)
  beta[1:r, 1:r] <- diag(1, r)
  
  sigma_i <- diag(1 / .0001, k)
  
  g_i <- sigma_i
  
  iterations <- data$model$iterations # Number of iterations of the Gibbs sampler
  burnin <- data$model$burnin # Number of burn-in draws
  draws <- iterations + burnin # Total number of draws
  
  # Data containers
  draws_alpha <- matrix(NA, k_alpha, iterations)
  draws_beta <- matrix(NA, k_beta, iterations)
  draws_pi <- matrix(NA, k * k_w, iterations)
  draws_gamma <- matrix(NA, k_gamma, iterations)
  draws_sigma <- matrix(NA, k^2, iterations)
  
  # Start Gibbs sampler
  for (draw in 1:draws) {
    
    # Draw conditional mean parameters
    temp <- post_coint_kls(y = y, beta = beta, w = w, x = x, sigma_i = sigma_i,
                           v_i = v_i, p_tau_i = p_tau_i, g_i = g_i,
                           gamma_mu_prior = a_mu_prior,
                           gamma_v_i_prior = a_v_i_prior)
    alpha <- temp$alpha
    beta <- temp$beta
    Pi <- temp$Pi
    gamma <- temp$Gamma
    
    # Draw variance-covariance matrix
    u <- y - Pi %*% w - matrix(gamma, k) %*% x
    sigma_scale_post <- solve(tcrossprod(u) + v_i * alpha %*% tcrossprod(crossprod(beta, p_tau_i) %*% beta, alpha))
    sigma_i <- matrix(rWishart(1, sigma_df_post, sigma_scale_post)[,, 1], k)
    sigma <- solve(sigma_i)
    
    # Update g_i
    g_i <- sigma_i
    
    # Store draws
    if (draw > burnin) {
      draws_alpha[, draw - burnin] <- alpha
      draws_beta[, draw - burnin] <- beta
      draws_pi[, draw - burnin] <- Pi
      draws_gamma[, draw - burnin] <- gamma
      draws_sigma[, draw - burnin] <- sigma
    }
  }
  beta <- apply(t(draws_beta) / t(draws_beta)[, 1], 2, mean) # Obtain means for every row
  beta <- matrix(beta, k_w) # Transform mean vector into a matrix
  beta <- round(beta, 3) # Round values
  dimnames(beta) <- list(dimnames(w)[[1]], NULL) # Rename matrix dimensions
  
  # Number of non-deterministic coefficients
  k_nondet <- (k_x - 4) * k
  return(list(draws_pi=draws_pi,
              draws_gamma=draws_gamma,
              draws_sigma=draws_sigma,
              beta=beta,
              k_nondet=k_nondet))
}



