# SPDX-License-Identifier: GPL-2.0+

ifeq ($(CONFIG_$(PHASE_)SKIP_LOWLEVEL_INIT),)
obj-y	:= mux.o
endif

obj-$(CONFIG_TI_I2C_BOARD_DETECT)		+= ../../ti/common/board_detect.o
obj-$(CONFIG_$(PHASE_)SUPPORT_EXTENSION_SCAN)	+= ../../ti/common/cape_detect.o

obj-y	+= board.o