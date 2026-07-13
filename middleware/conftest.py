"""Ensure the middleware package root is importable when running pytest.

Placing this at the middleware root puts that directory on ``sys.path`` so tests
can ``import app`` regardless of the working directory pytest is invoked from.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
