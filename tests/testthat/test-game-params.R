library(magrittr)

test_that('check_params returns warning if missing parameters',{
  expect_warning(check_params(default_params %>% dplyr::select(-rmN)),"missing rmN in params")
  expect_warning(check_params(default_params %>% dplyr::select(-rmN)),"missing rmN in params")
  expect_warning(check_params(default_params %>% dplyr::select(-rmN)),"missing rmN in params")
})

params_confined <- default_params
test_that('check_params returns warning if missing CONFINED parameters',{
  expect_warning(check_params(params_confined %>% dplyr::select(-Dff,-d0s)),"missing Dff, d0s in params")
  expect_warning(check_params(params_confined %>% dplyr::select(-d0s)),"missing d0s in params")
  expect_warning(check_params(params_confined %>% dplyr::select(-Dff)),"missing Dff in params")
})

params_unconfined <-
  default_params %>% dplyr::rename(PHIff = Dff, PHIss = Dss, PHIsf = Dsf, PHIfs = Dfs) %>%
  dplyr::mutate(dBs = 1, dBf = 2, h0s = 0.5, h0f = 0.5)
test_that('check_params returns correct aquifer type',{
  expect_equal(check_params(params_unconfined),"unconfined")
})
test_that('check_params returns warning if missing UNCONFINED parameters',{
  expect_warning(check_params(params_unconfined %>% dplyr::select(-PHIff,-dBs)),"missing PHIff, dBs in params")
  expect_warning(check_params(params_unconfined %>% dplyr::select(-dBs)),"missing dBs in params")
  expect_warning(check_params(params_unconfined %>% dplyr::select(-PHIff)),"missing PHIff in params")
})

params_both <- params_unconfined %>% dplyr::bind_cols(params_confined %>% dplyr::select(dplyr::matches("D[sfij][sfij]")))
test_that('check_params stops if UNCONFINED and CONFINED drawdown relationships supplied',{
  expect_error(check_params(params_both),"params should contain either Dix or PHIix, not both")
})

params_neither <- params_confined %>% dplyr::select(-dplyr::matches("D[sfij][sfij]"))
test_that('check_params stops if UNCONFINED and CONFINED drawdown relationships supplied',{
  expect_error(check_params(params_neither),"Missing drawdown parameters \\(Dxx or PHIxx\\) in params.")
})