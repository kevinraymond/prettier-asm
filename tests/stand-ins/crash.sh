#!/bin/sh
# Stand-in: dies on SIGSEGV. Expect 100% DIFFERENT.
kill -SEGV $$
