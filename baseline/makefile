##############################################################
#
# Standard Pin tool makefile.
# Build with:  make PIN_ROOT=<path to pin kit> obj-intel64/bprofile-with-gearing.so
# or place this directory under <pin kit>/source/tools/ and run: make
#
##############################################################

ifdef PIN_ROOT
CONFIG_ROOT := $(PIN_ROOT)/source/tools/Config
else
CONFIG_ROOT := ../Config
endif
include $(CONFIG_ROOT)/makefile.config
include makefile.rules
include $(TOOLS_ROOT)/Config/makefile.default.rules

##############################################################
