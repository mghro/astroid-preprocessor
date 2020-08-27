# astroid-preprocessor

Astroid's C++ preprocessor

## Build Instructions

At the moment, only Ubuntu Linux is supported. It's known to work on 20.04, but
it may work on other releases.

First, assuming you're not already developing with OCaml, run the following:

```shell
sudo apt-get install -y ocaml-nox opam pkg-config
opam init --disable-sandboxing
```

Note that `--disable-sandboxing` is only needed for WSL. If you're running
Ubuntu directly, it's safer to omit that.

Now install the necessary libraries.

```shell
opam install yaml
```

And finally, build it:

```shell
mkdir build
cd build
cmake -G"Unix Makefiles" ..
```

(Yes, this is using CMake at the moment even though there's no C++ code...)
