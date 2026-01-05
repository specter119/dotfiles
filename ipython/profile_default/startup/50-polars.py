import importlib.util

if importlib.util.find_spec('polars') is not None:
    import polars as pl

    pl.Config.set_tbl_rows(200)
    pl.Config.set_tbl_cols(50)
    pl.Config.set_fmt_str_lengths(100)
