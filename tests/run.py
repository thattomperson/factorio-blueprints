#!/usr/bin/env python3
"""Run the mocked-runtime tests: pip install lupa && python3 -I tests/run.py"""
import os, lupa
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = lupa.LuaRuntime()
L.globals().arg = L.table(root)
L.execute(open(os.path.join(root, "tests", "mock_game.lua")).read())
