#!/usr/bin/env python3
from pexpectutil import *
import sys

c = new_console(sys.argv[1])
login_and_set_prompt(c)

upload_file(c, sys.argv[2])

c.sendeof()
time.sleep(1)
c.sendcontrol(']')
