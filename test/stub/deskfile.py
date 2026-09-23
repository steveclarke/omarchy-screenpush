"""Run the real desk helper with the fixture's temporary passwd home."""

import os
import pwd
import runpy
from types import SimpleNamespace

pwd.getpwuid = lambda uid: SimpleNamespace(pw_dir=os.environ["SCREENPUSH_TEST_HOME"])
runpy.run_path(os.environ["SCREENPUSH_REAL_DESKFILE"], run_name="__main__")
