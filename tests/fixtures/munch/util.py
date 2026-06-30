import functools
def alpha(a, b):
    return a + b
class Gamma:
    def do_thing(self):
        return 1
@functools.cache
def cached(n):
    return n
