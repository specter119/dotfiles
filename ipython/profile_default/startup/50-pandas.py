import importlib.metadata
import importlib.util

if importlib.util.find_spec('pandas') is not None:
    _pd_ver = importlib.metadata.distribution('pandas').version
    if _pd_ver.rsplit('.', 1)[0] == '1.5':
        import warnings

        warnings.filterwarnings(
            action='ignore',
            message='will attempt to set the values inplace instead of always setting a new array',
            category=DeprecationWarning,
        )

    import pandas as pd

    pd.set_option('display.max_rows', 200)
    pd.set_option('display.max_columns', 50)
    pd.set_option('display.max_colwidth', 100)
    pd.set_option('display.precision', 4)
