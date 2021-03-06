library(rstan)
rstan_options(auto_write = T)

# i indexes points, j indexes visits, k indexes species.


# Define data size
n_cluster <- 40 # points are grouped into clusters, and cluster-by-species will ultimately be a random effect on occupancy
ppc <- 3 # three points per cluster
n_point <- n_cluster*ppc
n_species <- 20
n_visit <- rep(4, n_point)

# Define covariates (covariates associated with species visit and point; point covariates include continuous covariates that 
# do not vary within clusters as well as continuous covariates that do vary within clusters)
clusterID <- rep(c(1:n_cluster), ppc)
sp_cov1 <- runif(n_species) - .5
sp_cov2 <- runif(n_species) - .5
pt_cov1 <- runif(n_point) - .5
cl.cov.1 <- runif(n_cluster) - .5
pt_cov2 <- rep(NA, n_point)
for(i in 1:n_point){
  pt_cov2[i] <- cl.cov.1[clusterID[i]]
}

vis_cov1 <- matrix(data = NA, nrow = n_point, ncol = max(n_visit))
for(i in 1:n_point){
  vis_cov1[i, ] <- runif(n_visit[i]) - .5
}

exists_visit <- matrix(data = 0, nrow = n_point, ncol = max(n_visit))
for(i in 1:n_point){
  for(j in 1:n_visit[i]){
    exists_visit[i,j] <- 1
  }
}

# Define hyperparameters
occ.hyper <- list(b0 = c(0, .5), b1 = c(0, 1), b2 = 1, b3 = -1, b4 = c(0, .2),
                  b5 = c(1,2), b6 = 2)
b0 <- rnorm(n_species, occ.hyper$b0[1], occ.hyper$b0[2])
b1 <- matrix(data = rnorm(n_cluster*n_species, occ.hyper$b1[1], occ.hyper$b1[2]), nrow = n_cluster)
b2 <- occ.hyper$b2
b3 <- occ.hyper$b3
b4 <- rnorm(n_species, occ.hyper$b4[1], occ.hyper$b4[2])
b5 <- rnorm(n_species, occ.hyper$b5[1], occ.hyper$b5[2])
b6 <- occ.hyper$b6

det.hyper <- list(d0 = c(-2, .5), d1 = c(0, 1), d2 = 0, d3 = 1, d4 = c(0, .2),
                  d5 = c(2, .5))
d0 <- rnorm(n_species, det.hyper$d0[1], det.hyper$d0[2])
d1 <- matrix(data = rnorm(n_point*n_species, det.hyper$d1[1], det.hyper$d1[2]), nrow = n_point)
d2 <- det.hyper$d2
d3 <- det.hyper$d3
d4 <- rnorm(n_species, det.hyper$d4[1], det.hyper$d4[2])
d5 <- rnorm(n_species, det.hyper$d5[1], det.hyper$d5[2])

# The below simulation is super inefficient, but the version with for-loops helps me keep straight
# everything that is going on.

# Simulate parameters from hyperparameters 
logit.occ <- psi <- matrix(NA, nrow = n_point, ncol = n_species)
for(i in 1:n_point){
  for(k in 1:n_species){
    logit.occ[i, k] <- b0[k] + b1[clusterID[i],k] + b2*sp_cov1[k] + b3*sp_cov2[k] + 
      b4[k]*pt_cov1[i] + b5[k]*pt_cov2[i] + b6*sp_cov1[k]*pt_cov2[i]
    psi[i, k] <- boot::inv.logit(logit.occ[i, k])
  }
}

logit.det <- theta <- array(NA, dim = c(n_point, max(n_visit), n_species))
for(i in 1:n_point){
  for(j in 1:n_visit[i]){
    for(k in 1:n_species){
      logit.det[i, j, k] <- d0[k] + d2*sp_cov1[k] + d3*sp_cov2[k] + 
        d4[k]*pt_cov1[i] + d5[k]*vis_cov1[i,j]
      theta[i, j, k] <- boot::inv.logit(logit.det[i, j, k])
    }
  }
}


# simulate data from parameters
Z <- matrix(NA, nrow = n_point, ncol = n_species)
for(i in 1:n_point){
  for(k in 1:n_species){
    Z[i, k] <- rbinom(1, 1, psi[i, k])
  }
}

det_data <- array(NA, dim = c(n_point, max(n_visit), n_species))
for(i in 1:n_point){
  for(j in 1:n_visit[i]){
    for(k in 1:n_species){
      det_data[i,j,k] <- Z[i, k] * rbinom(1, 1, theta[i,j,k])
    }
  }
}

Q <- apply(det_data, c(1,3), function(x){return(as.numeric(sum(x) > 0))})


stan.model <- '
data {
  int<lower=1> n_point; //number of sites
  int<lower=1> n_visit; //fixed number of visits
  int<lower=1> n_species; //number of species
  int<lower=1> n_cluster; //number of clusters
  int<lower=0, upper=1> det_data[n_point, n_visit, n_species]; //detection history
  int<lower=0, upper=1> Q[n_point, n_species]; //at least one detection
  int<lower=0, upper=n_cluster> clusterID[n_point]; //cluster identifier (for random effects)
  vector[n_species] sp_cov1; //species covariate 1
  vector[n_species] sp_cov2; //species covariate 2
  vector[n_point] pt_cov1; //point covariate 1
  vector[n_point] pt_cov2; //point covariate 2
  matrix[n_point, n_visit] vis_cov1; //visit covariate 1
}
parameters {
  real mu_b0;
  real<lower=0> sigma_b0;
  vector[n_species] b0_raw;
  
  real<lower=0> sigma_b1;
  matrix[n_species, n_cluster] b1_raw;
  
  real b2;
  
  real b3;
  
  real mu_b4;
  real<lower=0> sigma_b4;
  vector[n_species] b4_raw;
  
  real mu_b5;
  real<lower=0> sigma_b5;
  vector[n_species] b5_raw;
  
  real b6;
  
  real mu_d0;
  real<lower=0> sigma_d0;
  vector[n_species] d0_raw;
  
  real d2;
  real d3;
  real mu_d4;
  real<lower=0> sigma_d4;
  vector[n_species] d4_raw;
  
  real mu_d5;
  real<lower=0> sigma_d5;
  vector[n_species] d5_raw;
}
transformed parameters{
  vector[n_species] b0 = mu_b0 + b0_raw * sigma_b0;
  matrix[n_species, n_cluster] b1 = b1_raw * sigma_b1;
  vector[n_species] b4 = mu_b4 + b4_raw * sigma_b4;
  vector[n_species] b5 = mu_b5 + b5_raw * sigma_b5;

  vector[n_species] d0 = mu_d0 + d0_raw * sigma_d0;

  vector[n_species] d4 = mu_d4 + d4_raw * sigma_d4;
  vector[n_species] d5 = mu_d5 + d5_raw * sigma_d5;
  real logit_psi[n_point, n_species];
  real logit_theta[n_point, n_visit, n_species];
  matrix[n_point, n_species] log_prob_increment;
  for(i in 1:n_point){
    for(k in 1:n_species){
      logit_psi[i,k] = b0[k] + b1[k, clusterID[i]] + b2*sp_cov1[k] + b3*sp_cov2[k] + 
                            b4[k]*pt_cov1[i] + b5[k]*pt_cov2[i] + b6*sp_cov1[k]*pt_cov2[i];
    }
  }
  for(i in 1:n_point){
    for(j in 1:n_visit){
      for(k in 1:n_species){
        logit_theta[i,j,k] = d0[k]  + d2*sp_cov1[k] + d3*sp_cov2[k] + 
                         d4[k]*pt_cov1[i] + 
                        d5[k]*vis_cov1[i,j];
      }
    }
  }
  
  for(i in 1:n_point){
    for(k in 1:n_species){
      if(Q[i,k] == 1)
        log_prob_increment[i,k] = log_inv_logit(logit_psi[i,k]) + 
                                    bernoulli_logit_lpmf(det_data[i,1,k] | logit_theta[i,1,k]) + 
                                    bernoulli_logit_lpmf(det_data[i,2,k] | logit_theta[i,2,k]) +
                                    bernoulli_logit_lpmf(det_data[i,3,k] | logit_theta[i,3,k]) +
                                    bernoulli_logit_lpmf(det_data[i,4,k] | logit_theta[i,4,k]);
      else
        log_prob_increment[i,k] = log_sum_exp(log_inv_logit(logit_psi[i,k]) + log1m_inv_logit(logit_theta[i,1,k]) + 
                                                    log1m_inv_logit(logit_theta[i,2,k]) + log1m_inv_logit(logit_theta[i,3,k]) + 
                                                    log1m_inv_logit(logit_theta[i,4,k]), 
                                                log1m_inv_logit(logit_psi[i,k]));
    }
  }
}
 
model {
  //Hyper-priors:
  mu_b0 ~ normal(0,10);
  b2 ~ normal(0,10);
  b3 ~ normal(0,10);
  mu_b4 ~ normal(0,10);
  mu_b5 ~ normal(0,10);
  b6 ~ normal(0,10);
  
  mu_d0 ~ normal(0,10);
  d2 ~ normal(0,10);
  d3 ~ normal(0,10);
  mu_d4 ~ normal(0,10);
  mu_d5 ~ normal(0,10);
  
  sigma_b0 ~ normal(0,10);
  sigma_b1 ~ normal(0,10);
  sigma_b4 ~ normal(0,10);
  sigma_b5 ~ normal(0,10);

  sigma_d0 ~ normal(0,10);
  sigma_d4 ~ normal(0,10);
  sigma_d5 ~ normal(0,10);
  
  //Random Effects
  b0_raw ~ normal(0, 1);
  to_vector(b1_raw) ~ normal(0, 1);
  b4_raw ~ normal(0, 1);
  b5_raw ~ normal(0, 1);

  d0_raw ~ normal(0, 1);
  
  d4_raw ~ normal(0, 1);
  d5_raw ~ normal(0, 1);
  
  //Likelihood (data level)
  target += sum(log_prob_increment);
}'


stan.data <- list(n_point = n_point, n_species = n_species, 
                  n_cluster = n_cluster, n_visit = 4,
                  det_data = det_data, 
                  Q = Q, 
                  clusterID = clusterID, 
                  sp_cov1 = sp_cov1, sp_cov2 = sp_cov2, 
                  pt_cov1 = pt_cov1, pt_cov2 = pt_cov2,
                  vis_cov1 = vis_cov1)

nc <- 4

stan.samples <- stan(model_code = stan.model, data = stan.data, iter = 2000, chains = nc, cores = nc,
                     pars = c('logit_psi', 'logit_theta', 'log_prob_increment', 'b1_raw', 'b1'),
                     include = FALSE, refresh = 10)

summary.samples <- summary(stan.samples)
which(summary.samples$summary[,9] == min(summary.samples$summary[,9]))
max(summary.samples$summary[,10])
object.size(stan.samples)


summary.samples$summary[c('mu_b0', 'sigma_b0', 'mu_d0', 'sigma_d0', 'sigma_b1', 'b2', 'b3'),]

dfs <- as.data.frame(stan.samples)
plot(dfs$mu_b0, dfs$mu_d0)
######

# 30 species, all params saved, small model:
#    min neff = 862
#    max R-hat = 1.004
#    grad. eval. range: .046 - .072
#    elapsed range: 7427 - 7490
#    object.size: 15178522976 bytes

# 30 species, few params saved, small model:
#    min neff = 809
#    max R-hat = 1.012
#    grad. eval. range: .049 - .077
#    elapsed range: 5649 - 6839


# 60 species, few params saved, 2000 iterations, small model:
#    min neff = 303.35
#    max R-hat = 1.022
#    grad. eval. range: .088 - .152
#    elapsed range: 13573 - 16148
#    object.size: 104002808 bytes

# 120 species, few params saved, 2000 iterations, small model:
#    min neff = 453.734
#    max R-hat = 1.014
#    grad. eval. range: .180 - .312
#    elapsed range: 25435 - 33187

# 240 species, few params saved, 2000 iterations, small model:
#    min neff = 229
#    max R-hat = 1.017
#    grad. eval. range: .363 - .531
#    elapsed range: 89908 - 97478

# 1500 species, few params saved, 2000 iterations, small model, CXX flags updated:
# Started near 1410h on 22/4/20, terminated on 28/4; chain 4 at 36%, all other chains near 10%
#    min neff =
#    max R-hat = 
#    grad. eval. range: 2.90 - 3.63
#    elapsed range: 
