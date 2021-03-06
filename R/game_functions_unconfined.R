# game_functions_unconfined.R

#' Evaluate the treaty in unconfined aquifer with linear cost
#'
#' Evaluate whether or not the treaty will be made where pumping cost is linear with depth.
#' @param params Parameter list (or data.frame with 1 row) containing
#' necessary parameters to evaluate the agreement in an unconfined case.
#' @details
#' Evaluate the treaty given social, economic, and geophysical parameters.
#'
#' Note that root finding proceeds in two steps for each of the First Besh, Nash Equilibrium, and Cheat scenarios:
#' \enumerate{
#' \item Pumping rates (for both players) are determined simultaneously to maximize utility based on the scenario (ie,
#' by finding the roots). Root finding stops immediately if the aquifer is fully depleted.
#' \item Pumping has to fall within the range [0, Qi] for both players. If it is outside this range, it is constrained
#' to be within the range. Then, pumping for each player is optimized individually given a fixed pumping rate for the
#' other player. The new values are then constrained, and the process repeats recursively until convergin on a solution
#' (or 500 tries). Within each iteration, root finding stops if the aquifer is fully depleted.
#' }
#' Note: if the aquifer is fully depleted in any of the solutions, this function will return 3 additional columns:
#' \code{AD_fb,AD_nash,AD_cheat}, representing logical values that indicate in which scenario the aquifer was depleted.
#' @return
#' Returns a 1-row tibble containing pumping, utility ranges needed for the treaty,
#' and whether or not there is a treaty (i.e., if zRange > 0)
#' @importFrom magrittr %>%
#' @keywords internal
#' @examples
#' \dontrun{
#' evaluate_treaty_unconfined_linear(example_params_unconfined)
#' }
evaluate_treaty_unconfined <- function(params) {
  # (eval_out <- evaluate_treaty(params_default()))
  # this function calculates abstraction from the game,
  # and determines whether or not a treaty is signed
  if(nrow(params)!=1){
    stop("This is an error message because params not 1 dimension")
  }
  params$Bs <- params$B
  params$Bf <- params$B
  params$phi0s <- params$h0s^2
  params$phi0f <- params$h0f^2

  if ("l" %in% names(params) & params$l != 1) {
    # because utility is nonlinear, need to make sure we don't overshoot qs, qf and fully deplete the aquifer
    q_guess <- get_q_aquifer_nearly_depleted(params)
    params$qs_guessT <- q_guess$qsT
    params$qf_guessT <- q_guess$qfT
    params$qs_guessN <- q_guess$qsN
    params$qf_guessN <- q_guess$qfN
    q_hat <- unconA_nl_qeval(params,unconA_nl_qhat0,unconA_nl_qhat2)
    q_star <- unconA_nl_qeval(params,unconA_nl_qstar0,unconA_nl_qstar2)
    q_double <- unconA_nl_qeval(params,unconA_nl_qdouble0,unconA_nl_qdouble2,qshat=q_hat$qs,qfhat=q_hat$qf)
    unconA_function_zMaxFrench <- unconA_nl_zMaxFrench
    unconA_function_zMinSwiss <- unconA_nl_zMinSwiss
  } else if (params$l == 1) {
    q_hat <- unconA_lin_qeval(params,unconA_lin_qhat0,unconA_lin_qhat2)
    q_star <- unconA_lin_qeval(params,unconA_lin_qstar0,unconA_lin_qstar2)
    q_double <- unconA_lin_qeval(params,unconA_lin_qdouble0,unconA_lin_qdouble2,qshat=q_hat$qs,qfhat=q_hat$qf)
    unconA_function_zMaxFrench <- unconA_lin_zMaxFrench
    unconA_function_zMinSwiss <- unconA_lin_zMinSwiss
  } else {
    stop("l must be in the range [0,1]")
  }


  q_vals <- tibble::tibble(qshat=q_hat$qs,qfhat=q_hat$qf,
                           qsstar=q_star$qs,qfstar=q_star$qf,
                           qsdouble=q_double$qs,qfdouble=q_double$qf)

  # is the aquifer depleted (AD) in any of the cases?
  AD_fb <- check_aquifer_depleted(q_vals$qshat,q_vals$qfhat,params,treaty=TRUE)
  AD_nash <- check_aquifer_depleted(q_vals$qsstar,q_vals$qfstar,params,treaty=FALSE)
  AD_cheat_2 <- check_aquifer_depleted(q_vals$qsdouble,q_vals$qfdouble,params,treaty=TRUE) # both are cheats
  AD_cheat_f <- check_aquifer_depleted(q_vals$qshat,q_vals$qfdouble,params,treaty=TRUE) # F is a cheat
  AD_cheat_s <- check_aquifer_depleted(q_vals$qsdouble,q_vals$qfhat,params,treaty=TRUE) # S is a cheat
  AD_cheat <- any(c(AD_cheat_2,AD_cheat_f,AD_cheat_s))
  AD_cols <- tibble::tibble()
  if (any(c(AD_fb,AD_nash,AD_cheat))) {
    AD_cols <- tibble::tibble(AD_fb=AD_fb,AD_nash=AD_nash,AD_cheat=AD_cheat)
  }

  # # get z constraints
  if (!AD_cheat_s) {
    zMaxFrench_calc <- unconA_function_zMaxFrench(params,q_vals)
  } else {
    zMaxFrench_calc <- -Inf
  }
  if (!AD_cheat_f) {
    zMinSwiss_calc <- unconA_function_zMinSwiss(params,q_vals)
  } else {
    zMinSwiss_calc <- Inf
  }
  zRange_calc <- round(zMaxFrench_calc - zMinSwiss_calc,6)

  treaty <- dplyr::case_when(
    zRange_calc>0 ~ "Y",
    zRange_calc<=0 ~ "N",
    any(c(AD_fb,AD_nash,AD_cheat)) ~ "D",
    TRUE ~ as.character(NA)
  )

  eval_return <- tibble::tibble(treaty=treaty,zRange=zRange_calc,
                                zMinSwiss=zMinSwiss_calc,zMaxFrench=zMaxFrench_calc) %>%
    dplyr::bind_cols(q_vals)
  if (any(c(AD_fb,AD_nash,AD_cheat))) {
    eval_return <- eval_return %>% dplyr::bind_cols(AD_cols)
  }
  return(eval_return)
}

#' Check if unconfined aquifer is fully depleted
#'
#' Is pumping enough to fully deplete the aquifer for either player?
#' @param params parameter data.frame with single row
#' @param treaty boolean value that determines the context for evaluation (e.g., for Nash should be \code{F}, for First Best should be \code{T})
#' @param qs pumping from player S
#' @param qf pumping from player F
#' @keywords internal
#' @return
#' Returns boolean value, TRUE if the aquifer has been fully depleted for some amount of pumping.
check_aquifer_depleted <- function(qs,qf,params,treaty) {
  if (treaty) {
    names(params)[match(c("rmT","PHIsrT","PHIfrT"),names(params))] <- c("rm","PHIsr","PHIfr")
  } else {
    names(params)[match(c("rmN","PHIsrN","PHIfrN"),names(params))] <- c("rm","PHIsr","PHIfr")
  }
  phis<-with(params,
             h0s^2-PHIsf*qf-PHIss*qs+PHIsr*rm
  )

  phif<-with(params,
             h0f^2-PHIff*qf-PHIfs*qs+PHIfr*rm
  )

  if (phis < 0 | phif < 0) {
    aquifer_depleted <- TRUE
  } else {
    aquifer_depleted <- FALSE
  }
  return(aquifer_depleted)
}


