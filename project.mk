#$(summary):@echo 显示
# Main Project Makefile
# This Makefile is included directly from the user project Makefile in order to call the component.mk
# makefiles of all components (in a separate make process) to build all the libraries, then links them
# together into the final file. If so, PWD is the project dir (we assume).
#为了调用component.mk编译所有的库文件,这个makefile文件由工程下的makefile文件直接调用，然后将他问链接到最终文件里。
#

#
# This makefile requires the environment variable IDF_PATH to be set to the top-level esp-idf directory
# where this file is located.
# 这个makefile要求设置环境变量IDF_PATH指向esp-idf所在的文件夹内
#
#防止文件名跟命令行冲突或者跟变量冲突

.PHONY: build-components menuconfig defconfig all build clean all_binaries check-submodules size size-components size-files size-symbols list-components

MAKECMDGOALS ?= all
all: all_binaries | check_python_dependencies
# see below for recipe of 'all' target
#
# # other components will add dependencies to 'all_binaries'. The
# reason all_binaries is used instead of 'all' is so that the flash
# target can build everything without triggering the per-component "to
# flash..." output targets.)

help:
	@echo "Welcome to Espressif IDF build system. Some useful make targets:"
	@echo ""
	@echo "make menuconfig - Configure IDF project"
	@echo "make defconfig - Set defaults for all new configuration options"
	@echo ""
	@echo "make all - Build app, bootloader, partition table"
	@echo "make flash - Flash app, bootloader, partition table to a chip"
	@echo "make clean - Remove all build output"
	@echo "make size - Display the static memory footprint of the app"
	@echo "make size-components, size-files - Finer-grained memory footprints"
	@echo "make size-symbols - Per symbol memory footprint. Requires COMPONENT=<component>"
	@echo "make erase_flash - Erase entire flash contents"
	@echo "make erase_ota - Erase ota_data partition. After that will boot first bootable partition (factory or OTAx)."
	@echo "make monitor - Run idf_monitor tool to monitor serial output from app"
	@echo "make simple_monitor - Monitor serial output on terminal console"
	@echo "make list-components - List all components in the project"
	@echo ""
	@echo "make app - Build just the app"
	@echo "make app-flash - Flash just the app"
	@echo "make app-clean - Clean just the app"
	@echo "make print_flash_cmd - Print the arguments for esptool when flash"
	@echo "make check_python_dependencies - Check that the required python packages are installed"
	@echo ""
	@echo "See also 'make bootloader', 'make bootloader-flash', 'make bootloader-clean', "
	@echo "'make partition_table', etc, etc."

# Non-interactive targets. Mostly, those for which you do not need to build a binary
#NON_INTERACTIVE_TARGET:defconfig clean% %clean help list-components print_flash_cmd check_python_dependencies
NON_INTERACTIVE_TARGET += defconfig clean% %clean help list-components print_flash_cmd check_python_dependencies

# dependency checks
ifndef MAKE_RESTARTS
ifeq ("$(filter 4.% 3.81 3.82,$(MAKE_VERSION))","")
$(warning esp-idf build system only supports GNU Make versions 3.81 or newer. You may see unexpected results with other Makes.)
endif


ifdef MSYSTEM
ifneq ("$(MSYSTEM)","MINGW32")
$(warning esp-idf build system only supports MSYS2 in "MINGW32" mode. Consult the ESP-IDF documentation for details.)
endif
endif  # MSYSTEM

endif  # MAKE_RESTARTS

# can't run 'clean' along with any non-clean targets
ifneq ("$(filter clean% %clean,$(MAKECMDGOALS))" ,"")
ifneq ("$(filter-out clean% %clean,$(MAKECMDGOALS))", "")
$(error esp-idf build system doesn't support running 'clean' targets along with any others. Run 'make clean' and then run other targets separately.)
endif
endif

OS ?=

# make IDF_PATH a "real" absolute path
# * works around the case where a shell character is embedded in the environment variable value.
# * changes Windows-style C:/blah/ paths to MSYS style /c/blah
ifeq ("$(OS)","Windows_NT")
# On Windows MSYS2, make wildcard function returns empty string for paths of form /xyz
# where /xyz is a directory inside the MSYS root - so we don't use it
#如果是window系统返回绝对路径
else
#如果是非windows系统返回绝对路径
SANITISED_IDF_PATH:=$(realpath $(wildcard $(IDF_PATH)))
endif
#把绝对路径加载到环境变量
export IDF_PATH := $(SANITISED_IDF_PATH)

ifndef IDF_PATH
$(error IDF_PATH variable is not set to a valid directory.)
endif

#判断环境变量是否能够加载成功，
#检测IDF_PATH变量，IDF_PATH变量可能为预先设置的环境变量，也可能是从命令行传入的路径，这里主要检测从IDF_PATH是否正确获取到
ifneq ("$(IDF_PATH)","$(SANITISED_IDF_PATH)")
# implies IDF_PATH was overriden on make command line.
# Due to the way make manages variables, this is hard to account for
#
# if you see this error, do the shell expansion in the shell ie
# make IDF_PATH=~/blah not make IDF_PATH="~/blah"
$(error If IDF_PATH is overriden on command line, it must be an absolute path with no embedded shell special characters)
endif

ifneq ("$(IDF_PATH)","$(subst :,,$(IDF_PATH))")
$(error IDF_PATH cannot contain colons. If overriding IDF_PATH on Windows, use MSYS Unix-style /c/dir instead of C:/dir)
endif

# 保存原来的MAKEFLAGS，并设置新的MAKEFLAGS
# disable built-in make rules, makes debugging saner
MAKEFLAGS_OLD := $(MAKEFLAGS)
MAKEFLAGS +=-rR

# Default path to the project: we assume the Makefile including this file
# is in the project directory
#获取工程项目当前路径
#$(MAKEFILE_LIST)是所有.mk文件
#$(dir $(firstword $(MAKEFILE_LIST)))输出工程文件下为MAKEFILE
#$(dir $(firstword $(MAKEFILE_LIST)))为当前文件夹
#$(abspath $(dir $(firstword $(MAKEFILE_LIST))))为当前makefile绝对路径
ifndef PROJECT_PATH
PROJECT_PATH := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
export PROJECT_PATH
endif

# A list of the "common" makefiles, to use as a target dependency
#输出为project.mk common.mk component_wrapper.mk和工程目录下makefile放到shell当前环境变量
COMMON_MAKEFILES := $(abspath $(IDF_PATH)/make/project.mk $(IDF_PATH)/make/common.mk $(IDF_PATH)/make/component_wrapper.mk $(firstword $(MAKEFILE_LIST)))
export COMMON_MAKEFILES

# The directory where we put all objects/libraries/binaries. The project Makefile can
# configure this if needed.
#创建build标签
ifndef BUILD_DIR_BASE
BUILD_DIR_BASE := $(PROJECT_PATH)/build
endif
export BUILD_DIR_BASE

# Component directories. These directories are searched for components (either the directory is a component,
# or the directory contains subdirectories which are components.)
# The project Makefile can override these component dirs, or add extras via EXTRA_COMPONENT_DIRS
#加载文件组件components和工程代码main代码和components
#例如ulp工程输出：
#/home/fyy/esp_demo/ulp/components /home/fyy/esp/esp-idf/components /home/fyy/esp_demo/ulp/main
ifndef COMPONENT_DIRS
EXTRA_COMPONENT_DIRS ?=
COMPONENT_DIRS := $(PROJECT_PATH)/components $(EXTRA_COMPONENT_DIRS) $(IDF_PATH)/components $(PROJECT_PATH)/main
endif
export COMPONENT_DIRS

ifdef SRCDIRS
$(warning SRCDIRS variable is deprecated. These paths can be added to EXTRA_COMPONENT_DIRS or COMPONENT_DIRS instead.)
COMPONENT_DIRS += $(abspath $(SRCDIRS))
endif

# The project Makefile can define a list of components, but if it does not do this we just take all available components
# in the component dirs. A component is COMPONENT_DIRS directory, or immediate subdirectory,
# which contains a component.mk file.
#
# Use the "make list-components" target to debug this step.
#获取所有子模块
ifndef COMPONENTS
# Find all component names. The component names are the same as the
# directories they're in, so /bla/components/mycomponent/component.mk -> mycomponent.
#获取所有COMPONENTS下makefile绝对路径
COMPONENTS := $(dir $(foreach cd,$(COMPONENT_DIRS),                           \
					$(wildcard $(cd)/*/component.mk) $(wildcard $(cd)/component.mk) \
				))
#获取所有COMPONENTS名字
COMPONENTS := $(sort $(foreach comp,$(COMPONENTS),$(lastword $(subst /, ,$(comp)))))
endif
# After a full manifest of component names is determined, subtract the ones explicitly omitted by the project Makefile.
ifdef EXCLUDE_COMPONENTS
COMPONENTS := $(filter-out $(subst ",,$(EXCLUDE_COMPONENTS)), $(COMPONENTS)) 
# to keep syntax highlighters happy: "))
endif
export COMPONENTS

# Resolve all of COMPONENTS into absolute paths in COMPONENT_PATHS.
#
# If a component name exists in multiple COMPONENT_DIRS, we take the first match.
#
# NOTE: These paths must be generated WITHOUT a trailing / so we
# can use $(notdir x) to get the component name.
#获取COMPONENT绝对路径
COMPONENT_PATHS := $(foreach comp,$(COMPONENTS),$(firstword $(foreach cd,$(COMPONENT_DIRS),$(wildcard $(dir $(cd))$(comp) $(cd)/$(comp)))))
export COMPONENT_PATHS

TEST_COMPONENTS ?=
TEST_EXCLUDE_COMPONENTS ?=
TESTS_ALL ?=

# If TESTS_ALL set to 1, set TEST_COMPONENTS_LIST to all components.
# Otherwise, use the list supplied in TEST_COMPONENTS.
#测试COMPONENTS名字输出
ifeq ($(TESTS_ALL),1)
TEST_COMPONENTS_LIST := $(filter-out $(TEST_EXCLUDE_COMPONENTS), $(COMPONENTS))
else
TEST_COMPONENTS_LIST := $(TEST_COMPONENTS)
endif
#h获取COMPONENTS包含test文件夹绝对路径
TEST_COMPONENT_PATHS := $(foreach comp,$(TEST_COMPONENTS_LIST),$(firstword $(foreach dir,$(COMPONENT_DIRS),$(wildcard $(dir)/$(comp)/test))))
#h获取COMPONENTS下包含test文件夹名字（不是绝对路径）
TEST_COMPONENT_NAMES := $(foreach comp,$(TEST_COMPONENT_PATHS),$(lastword $(subst /, ,$(dir $(comp))))_test)

# Initialise project-wide variables which can be added to by
# each component.
#
# These variables are built up via the component_project_vars.mk
# generated makefiles (one per component).
#
# See docs/build-system.rst for more details.
COMPONENT_INCLUDES :=
COMPONENT_LDFLAGS :=
COMPONENT_SUBMODULES :=
COMPONENT_LIBRARIES :=

# COMPONENT_PROJECT_VARS is the list of component_project_vars.mk generated makefiles
# for each component.
#
# Including $(COMPONENT_PROJECT_VARS) builds the COMPONENT_INCLUDES,
# COMPONENT_LDFLAGS variables and also targets for any inter-component
# dependencies.
#
# See the component_project_vars.mk target in component_wrapper.mk
#加后缀函数: $(addsuffix <suffix>,<names...>)
#功能: 把后缀 <suffix> 加到 <names> 中的每个单词后面
#返回: 加过后缀的文件名序列
#取文件函数: $(notdir <names...>)

#功能: 从文件名序列 <names> 中取出非目录部分
#返回: 文件名序列 <names> 中的非目录部分
#在工程目录build文件夹下创建.mk文件（绝对路径）
COMPONENT_PROJECT_VARS := $(addsuffix /component_project_vars.mk,$(notdir $(COMPONENT_PATHS) ) $(TEST_COMPONENT_NAMES))
COMPONENT_PROJECT_VARS := $(addprefix $(BUILD_DIR_BASE)/,$(COMPONENT_PROJECT_VARS))
# this line is -include instead of include to prevent a spurious error message on make 3.81
#使用“include FILENAMES...”，make程序处理时，如果“FILENAMES”列表中的任何一个文件不能正常读取而且不存在一个创建此文件的规则时make程序将会提示错误并退出。
#使用“-include FILENAMES...”的情况是，当所包含的文件不存在或者不存在一个规则去创建它，make程序会继续执行，只有真正由于不能正确完成终极目标的重建时（某些必需的目标无法在当前已读取的makefile文件内容中找到正确的重建规则），才会提示致命错误并退出。
-include $(COMPONENT_PROJECT_VARS)
# Also add to工程目录-level project include path, for top-level includes
#获取COMPONENT路径
# Also add top-level project include path, for top-level includes
COMPONENT_INCLUDES += $(abspath $(BUILD_DIR_BASE)/include/)

export COMPONENT_INCLUDES

# Set variables common to both project & component
include $(IDF_PATH)/make/common.mk

all:
ifdef CONFIG_SECURE_BOOT_ENABLED
	@echo "(Secure boot enabled, so bootloader not flashed automatically. See 'make bootloader' output)"
ifndef CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES
	@echo "App built but not signed. Sign app & partition data before flashing, via espsecure.py:"
	@echo "espsecure.py sign_data --keyfile KEYFILE $(APP_BIN)"
	@echo "espsecure.py sign_data --keyfile KEYFILE $(PARTITION_TABLE_BIN)"
endif
	@echo "To flash app & partition table, run 'make flash' or:"
else
	@echo "To flash all build output, run 'make flash' or:"
endif
	@echo $(ESPTOOLPY_WRITE_FLASH) $(ESPTOOL_ALL_FLASH_ARGS)


# If we have `version.txt` then prefer that for extracting IDF version
#获取版本号
ifeq ("$(wildcard ${IDF_PATH}/version.txt)","")
IDF_VER := $(shell cd ${IDF_PATH} && git describe --always --tags --dirty)
else
IDF_VER := `cat ${IDF_PATH}/version.txt`
endif

# Set default LDFLAGS
#-nostdlib 不连接系统标准启动文件和标准库文件，只把指定的文件传递给连接器。
#--gc-sections：这是avr-ld的参数，通过-Wl,<option>由gcc把option里的参数传递给avr-ld。它使得链接器ld链接时删除不用的段。这样，因为每个函数自成一段（即可以看作函数=段），如果有某个函数未被任何函数/段调用，则ld不会链接它。
#-static	在支持动态链接的系统上，阻止连接共享库。该选项在其它系统上 无效。
#添加gcc 、stdc++ 、gcov等库，并通过COMPONENT_LDFLAGS添加用户需要添加的链接flag，并在反复在搜索目标文件、变量等
#设置为小端编译
EXTRA_LDFLAGS ?=
LDFLAGS ?= -nostdlib \
	-u call_user_start_cpu0	\
	$(EXTRA_LDFLAGS) \
	-Wl,--gc-sections	\
	-Wl,-static	\
	-Wl,--start-group	\
	$(COMPONENT_LDFLAGS) \
	-lgcc \
	-lstdc++ \
	-lgcov \
	-Wl,--end-group \
	-Wl,-EL

# Set default CPPFLAGS, CFLAGS, CXXFLAGS
# These are exported so that components can use them when compiling.
# If you need your component to add CFLAGS/etc for it's own source compilation only, set CFLAGS += in your component's Makefile.
# If you need your component to add CFLAGS/etc globally for all source
#  files, set CFLAGS += in your component's Makefile.projbuild
# If you need to set CFLAGS/CPPFLAGS/CXXFLAGS at project level, set them in application Makefile
#  before including project.mk. Default flags will be added before the ones provided in application Makefile.

# CPPFLAGS used by C preprocessor
# If any flags are defined in application Makefile, add them at the end. 
#-M:输出为project
#-MMD：和上面的那个一样，但是它将忽略由#include造成的依赖关系
#-MMD：和-MM相同，但是输出将导入到.d的文件里面:
CPPFLAGS ?=
EXTRA_CPPFLAGS ?=
CPPFLAGS := -DESP_PLATFORM -D IDF_VER=\"$(IDF_VER)\" -MMD -MP $(CPPFLAGS) $(EXTRA_CPPFLAGS)

#打印输出标志
#-Wall 是使能所有警告。
#-Werror=all:把所有的告警信息转化为错误信息，并在告警发生时终止编译过程
#-Wno-error:把以下警告变成错误
# Warnings-related flags relevant both for C and C++
# Warnings-related flags relevant both for C and C++
COMMON_WARNING_FLAGS = -Wall -Werror=all \
	-Wno-error=unused-function \
	-Wno-error=unused-but-set-variable \
	-Wno-error=unused-variable \
	-Wno-error=deprecated-declarations \
	-Wextra \
	-Wno-unused-parameter -Wno-sign-compare

ifdef CONFIG_DISABLE_GCC8_WARNINGS
COMMON_WARNING_FLAGS += -Wno-parentheses \
	-Wno-sizeof-pointer-memaccess \
	-Wno-clobbered \
	-Wno-format-overflow \
	-Wno-stringop-truncation \
	-Wno-misleading-indentation \
	-Wno-cast-function-type \
	-Wno-implicit-fallthrough \
	-Wno-unused-const-variable \
	-Wno-switch-unreachable \
	-Wno-format-truncation \
	-Wno-memset-elt-size \
	-Wno-int-in-bool-context
endif

ifdef CONFIG_WARN_WRITE_STRINGS
COMMON_WARNING_FLAGS += -Wwrite-strings
endif #CONFIG_WARN_WRITE_STRINGS

# 优化编译，只编译进用到的sections，使用长跳转来代替段跳转，不连接标准启动文件和标准库文件，只将指定文件传递给连接器
#-ffunction-sections -fdata-sections 只把有用代码编译进去，减少程序大小
#对于CPU是PPC604类型的，动态下载的.out文件编译的时候必须要加这个编译选型，加了后会使用长跳转指令代替短跳转指令
#Force bitfield accesses to match their type width
#-nostdlib:不连接系统标准启动文件和标准库文件，只把指定的文件传递给连接器。
# Flags which control code generation and dependency generation, both for C and C++
COMMON_FLAGS = \
	-ffunction-sections -fdata-sections \
	-fstrict-volatile-bitfields \
	-mlongcalls \
	-nostdlib

ifndef IS_BOOTLOADER_BUILD
# stack protection (only one option can be selected in menuconfig)
ifdef CONFIG_STACK_CHECK_NORM
COMMON_FLAGS += -fstack-protector
endif
ifdef CONFIG_STACK_CHECK_STRONG
COMMON_FLAGS += -fstack-protector-strong
endif
ifdef CONFIG_STACK_CHECK_ALL
COMMON_FLAGS += -fstack-protector-all
endif
endif

# Optimization flags are set based on menuconfig choice
ifdef CONFIG_OPTIMIZATION_LEVEL_RELEASE
OPTIMIZATION_FLAGS = -Os
else
OPTIMIZATION_FLAGS = -Og
endif

ifdef CONFIG_OPTIMIZATION_ASSERTIONS_DISABLED
CPPFLAGS += -DNDEBUG
endif

# Enable generation of debugging symbols
# (we generate even in Release mode, as this has no impact on final binary size.)
DEBUG_FLAGS ?= -ggdb

# List of flags to pass to C compiler
# If any flags are defined in application Makefile, add them at the end.
CFLAGS ?=
EXTRA_CFLAGS ?=
CFLAGS := $(strip \
	-std=gnu99 \
	$(OPTIMIZATION_FLAGS) $(DEBUG_FLAGS) \
	$(COMMON_FLAGS) \
	$(COMMON_WARNING_FLAGS) -Wno-old-style-declaration \
	$(CFLAGS) \
	$(EXTRA_CFLAGS))

# List of flags to pass to C++ compiler
# If any flags are defined in application Makefile, add them at the end.
CXXFLAGS ?=
EXTRA_CXXFLAGS ?=
CXXFLAGS := $(strip \
	-std=gnu++11 \
	-fno-rtti \
	$(OPTIMIZATION_FLAGS) $(DEBUG_FLAGS) \
	$(COMMON_FLAGS) \
	$(COMMON_WARNING_FLAGS) \
	$(CXXFLAGS) \
	$(EXTRA_CXXFLAGS))

ifdef CONFIG_CXX_EXCEPTIONS
CXXFLAGS += -fexceptions
else
CXXFLAGS += -fno-exceptions
endif

ARFLAGS := cru

export CFLAGS CPPFLAGS CXXFLAGS ARFLAGS

# Set default values that were not previously defined
CC ?= gcc
LD ?= ld
AR ?= ar
OBJCOPY ?= objcopy
SIZE ?= size

#设置主机编译链接等工具以及交叉工具
# Set host compiler and binutils
HOSTCC := $(CC)
HOSTLD := $(LD)
HOSTAR := $(AR)
HOSTOBJCOPY := $(OBJCOPY)
HOSTSIZE := $(SIZE)
export HOSTCC HOSTLD HOSTAR HOSTOBJCOPY SIZE

#设置交叉编译工具并去除引号
# Set target compiler. Defaults to whatever the user has
# configured as prefix + ye olde gcc commands
CC := $(call dequote,$(CONFIG_TOOLPREFIX))gcc
CXX := $(call dequote,$(CONFIG_TOOLPREFIX))c++
LD := $(call dequote,$(CONFIG_TOOLPREFIX))ld
AR := $(call dequote,$(CONFIG_TOOLPREFIX))ar
OBJCOPY := $(call dequote,$(CONFIG_TOOLPREFIX))objcopy
SIZE := $(call dequote,$(CONFIG_TOOLPREFIX))size
export CC CXX LD AR OBJCOPY SIZE

COMPILER_VERSION_STR := $(shell $(CC) -dumpversion)
COMPILER_VERSION_NUM := $(subst .,,$(COMPILER_VERSION_STR))
GCC_NOT_5_2_0 := $(shell expr $(COMPILER_VERSION_STR) != "5.2.0")
export COMPILER_VERSION_STR COMPILER_VERSION_NUM GCC_NOT_5_2_0

CPPFLAGS += -DGCC_NOT_5_2_0=$(GCC_NOT_5_2_0)
export CPPFLAGS

PYTHON=$(call dequote,$(CONFIG_PYTHON))

#生成文件
# the app is the main executable built by the project
APP_ELF:=$(BUILD_DIR_BASE)/$(PROJECT_NAME).elf
APP_MAP:=$(APP_ELF:.elf=.map)
APP_BIN:=$(APP_ELF:.elf=.bin)

# Include any Makefile.projbuild file letting components add
# configuration at the project level
# 递归查找各文件夹下的Makefile.projbuild文件
define includeProjBuildMakefile
$(if $(V),$$(info including $(1)/Makefile.projbuild...))
COMPONENT_PATH := $(1)
include $(1)/Makefile.projbuild
endef
$(foreach componentpath,$(COMPONENT_PATHS), \
	$(if $(wildcard $(componentpath)/Makefile.projbuild), \
		$(eval $(call includeProjBuildMakefile,$(componentpath)))))

# once we know component paths, we can include the config generation targets
#
# (bootloader build doesn't need this, config is exported from top-level)
#编译bootloader不包含project_config
ifndef IS_BOOTLOADER_BUILD
include $(IDF_PATH)/make/project_config.mk
endif

# ELF depends on the library archive files for COMPONENT_LIBRARIES
# the rules to build these are emitted as part of GenerateComponentTarget below
#
# also depends on additional dependencies (linker scripts & binary libraries)
# stored in COMPONENT_LINKER_DEPS, built via component.mk files' COMPONENT_ADD_LINKER_DEPS variable
#编译所有component .a文件，并且拷贝到app.elf
#COMPONENT_LIBRARIES :app_trace app_update asio aws_iot bootloader_support bt coap console cxx driver esp-tls esp32 esp_adc_cal esp_http_client esp_https_ota ethernet expat fatfs freertos heap http_server idf_test jsmn json libsodium log lwip main mbedtls mdns micro-ecc newlib nghttp nvs_flash openssl pthread sdmmc smartconfig_ack soc spi_flash spiffs tcpip_adapter ulp vfs wear_levelling wpa_supplicant xtensa-debug-module
#BUILD_DIR_BASE:/home/fyy/esp_demo/hello_world/build
#编译esp32文件夹下.a 文件 COMPONENT_LINKER_DEPS：/home/fyy/esp/esp-idf/components/esp32/lib/libcore.a /home/fyy/esp/esp-idf/components/esp32/lib/librtc.a /home/fyy/esp/esp-idf/components/esp32/lib/libnet80211.a /home/fyy/esp/esp-idf/components/esp32/lib/libpp.a /home/fyy/esp/esp-idf/components/esp32/lib/libwpa.a /home/fyy/esp/esp-idf/components/esp32/lib/libsmartconfig.a /home/fyy/esp/esp-idf/components/esp32/lib/libcoexist.a /home/fyy/esp/esp-idf/components/esp32/lib/libwps.a /home/fyy/esp/esp-idf/components/esp32/lib/libwpa2.a /home/fyy/esp/esp-idf/components/esp32/lib/libespnow.a /home/fyy/esp/esp-idf/components/esp32/lib/libphy.a /home/fyy/esp/esp-idf/components/esp32/lib/libmesh.a /home/fyy/esp/esp-idf/components/esp32/ld/esp32.common.ld /home/fyy/esp/esp-idf/components/esp32/ld/esp32.rom.ld /home/fyy/esp/esp-idf/components/esp32/ld/esp32.peripherals.ld /home/fyy/esp/esp-idf/components/esp32/ld/esp32.rom.libgcc.ld /home/fyy/esp/esp-idf/components/esp32/ld/esp32.rom.spiram_incompatible_fns.ld /home/fyy/esp/esp-idf/components/newlib/lib/libc.a /home/fyy/esp/esp-idf/components/newlib/lib/libm.a
#patsubst：
COMPONENT_LINKER_DEPS ?=
$(APP_ELF): $(foreach libcomp,$(COMPONENT_LIBRARIES),$(BUILD_DIR_BASE)/$(libcomp)/lib$(libcomp).a) $(COMPONENT_LINKER_DEPS) $(COMPONENT_PROJECT_VARS)
	$(summary) LD $(patsubst $(PWD)/%,%,$@)
	$(CC) $(LDFLAGS) -o $@ -Wl,-Map=$(APP_MAP)

#只编译app，可直接使用make 调用
app: $(APP_BIN) partition_table_get_info
ifeq ("$(CONFIG_SECURE_BOOT_ENABLED)$(CONFIG_SECURE_BOOT_BUILD_SIGNED_BINARIES)","y") # secure boot enabled, but remote sign app image
	@echo "App built but not signed. Signing step via espsecure.py:"
	@echo "espsecure.py sign_data --keyfile KEYFILE $(APP_BIN)"
	@echo "Then flash app command is:"
	@echo $(ESPTOOLPY_WRITE_FLASH) $(APP_OFFSET) $(APP_BIN)
else
	@echo "App built. Default flash app command is:"
	@echo $(ESPTOOLPY_WRITE_FLASH) $(APP_OFFSET) $(APP_BIN)
endif

.PHONY: check_python_dependencies

# Notify users when some of the required python packages are not installed
# 检查python依赖文件是否安装，直接通过make 调用
check_python_dependencies:
ifndef IS_BOOTLOADER_BUILD
	$(PYTHON) $(IDF_PATH)/tools/check_python_dependencies.py
endif

all_binaries: $(APP_BIN)

$(BUILD_DIR_BASE):
	mkdir -p $(BUILD_DIR_BASE)

# Macro for the recursive sub-make for each component
# $(1) - component directory
# $(2) - component name only
#
# Is recursively expanded by the GenerateComponentTargets macro
#make所有组件
#当make的目标为all时,-C $(KDIR) 指明跳转到内核源码目录下读取那里的Makefile
#-f 指定读取一个 makefile 来代替缺省的 makefile。如果 Makefile 是 -（连字符），那么读取标准输入。可以指定多个 makefile 并按指定的顺序读取
define ComponentMake
+$(MAKE) -C $(BUILD_DIR_BASE)/$(2) -f $(IDF_PATH)/make/component_wrapper.mk COMPONENT_MAKEFILE=$(1)/component.mk COMPONENT_NAME=$(2)
endef

# Generate top-level component-specific targets for each component
# $(1) - path to component dir
# $(2) - name of component
#
define GenerateComponentTargets
.PHONY: component-$(2)-build component-$(2)-clean

component-$(2)-build: check-submodules $(call prereq_if_explicit, component-$(2)-clean) | $(BUILD_DIR_BASE)/$(2)
	$(call ComponentMake,$(1),$(2)) build

component-$(2)-clean: | $(BUILD_DIR_BASE)/$(2) $(BUILD_DIR_BASE)/$(2)/component_project_vars.mk
	$(call ComponentMake,$(1),$(2)) clean

#创建文件夹，如果存在不报错，如果父文件夹不存在就重新创建
$(BUILD_DIR_BASE)/$(2):
	@mkdir -p $(BUILD_DIR_BASE)/$(2)

# tell make it can build any component's library by invoking the -build target
# (this target exists for all components even ones which don't build libraries, but it's
# only invoked for the targets whose libraries appear in COMPONENT_LIBRARIES and hence the
# APP_ELF dependencies.)
$(BUILD_DIR_BASE)/$(2)/lib$(2).a: component-$(2)-build
	$(details) "Target '$$^' responsible for '$$@'" # echo which build target built this file

# add a target to generate the component_project_vars.mk files that
# are used to inject variables into project make pass (see matching
# component_project_vars.mk target in component_wrapper.mk).
#
# If any component_project_vars.mk file is out of date, the make
# process will call this target to rebuild it and then restart.
#
$(BUILD_DIR_BASE)/$(2)/component_project_vars.mk: $(1)/component.mk $(COMMON_MAKEFILES) $(SDKCONFIG_MAKEFILE) | $(BUILD_DIR_BASE)/$(2)
	$(call ComponentMake,$(1),$(2)) component_project_vars.mk
endef

#取文件函数: $(notdir <names...>)功能: 从文件名序列 <names> 中取出非目录部分 返回: 文件名序列 <names> 中的非目录部分
#$(foreach <var>,<list>,<text>)这个函数的意思是，把参数<list>;中的单词逐一取出放到参数<var>;所指定的变量中，然后再执行< text>;所包含的表达式。
#$(eval text)它的意思是 text 的内容将作为makefile的一部分而被make解析和执行。
$(foreach component,$(COMPONENT_PATHS),$(eval $(call GenerateComponentTargets,$(component),$(notdir $(component)))))
$(foreach component,$(TEST_COMPONENT_PATHS),$(eval $(call GenerateComponentTargets,$(component),$(lastword $(subst /, ,$(dir $(component))))_test)))

#说明：该函数将前缀 <prefix> 加到各个 <name> 的前面去。
#加后缀函数: $(addsuffix <suffix>,<names...>)
#功能: 把后缀 <suffix> 加到 <names> 中的每个单词后面
#返回: 加过后缀的文件名序列
app-clean: $(addprefix component-,$(addsuffix -clean,$(notdir $(COMPONENT_PATHS))))
	$(summary) RM $(APP_ELF)
	rm -f $(APP_ELF) $(APP_BIN) $(APP_MAP)

size: $(APP_ELF) | check_python_dependencies
	$(PYTHON) $(IDF_PATH)/tools/idf_size.py $(APP_MAP)

size-files: $(APP_ELF) | check_python_dependencies
	$(PYTHON) $(IDF_PATH)/tools/idf_size.py --files $(APP_MAP)

size-components: $(APP_ELF) | check_python_dependencies
	$(PYTHON) $(IDF_PATH)/tools/idf_size.py --archives $(APP_MAP)

size-symbols: $(APP_ELF) | check_python_dependencies
ifndef COMPONENT
	$(error "ERROR: Please enter the component to look symbols for, e.g. COMPONENT=heap")
else
	$(PYTHON) $(IDF_PATH)/tools/idf_size.py --archive_details lib$(COMPONENT).a $(APP_MAP)
endif

# NB: this ordering is deliberate (app-clean & bootloader-clean before
# _config-clean), so config remains valid during all component clean
# targets
config-clean: app-clean bootloader-clean
clean: app-clean bootloader-clean config-clean

# phony target to check if any git submodule listed in COMPONENT_SUBMODULES are missing
# or out of date, and exit if so. Components can add paths to this variable.
#
# This only works for components inside IDF_PATH
check-submodules:
# Check if .gitmodules exists, otherwise skip submodule check, assuming flattened structure
ifneq ("$(wildcard ${IDF_PATH}/.gitmodules)","")

# Dump the git status for the whole working copy once, then grep it for each submodule. This saves a lot of time on Windows.
GIT_STATUS := $(shell cd ${IDF_PATH} && git status --porcelain --ignore-submodules=dirty)

# Generate a target to check this submodule
# $(1) - submodule directory, relative to IDF_PATH

define GenerateSubmoduleCheckTarget
check-submodules: $(IDF_PATH)/$(1)/.git
$(IDF_PATH)/$(1)/.git:
	@echo "WARNING: Missing submodule $(1)..."
	[ -e ${IDF_PATH}/.git ] || ( echo "ERROR: esp-idf must be cloned from git to work."; exit 1)
	[ -x "$(shell which git)" ] || ( echo "ERROR: Need to run 'git submodule init $(1)' in esp-idf root directory."; exit 1)
	@echo "Attempting 'git submodule update --init $(1)' in esp-idf root directory..."
	cd ${IDF_PATH} && git submodule update --init $(1)

# Parse 'git status' output to check if the submodule commit is different to expected
ifneq ("$(filter $(1),$(GIT_STATUS))","")
$$(info WARNING: esp-idf git submodule $(1) may be out of date. Run 'git submodule update' in IDF_PATH dir to update.)
endif
endef

# filter/subst in expression ensures all submodule paths begin with $(IDF_PATH), and then strips that prefix
# so the argument is suitable for use with 'git submodule' commands
$(foreach submodule,$(subst $(IDF_PATH)/,,$(filter $(IDF_PATH)/%,$(COMPONENT_SUBMODULES))),$(eval $(call GenerateSubmoduleCheckTarget,$(submodule))))
endif # End check for .gitmodules existence


# PHONY target to list components in the build and their paths
list-components:
	$(info $(call dequote,$(SEPARATOR)))
	$(info COMPONENT_DIRS (components searched for here))
	$(foreach cd,$(COMPONENT_DIRS),$(info $(cd)))
	$(info $(call dequote,$(SEPARATOR)))
	$(info TEST_COMPONENTS (list of test component names))
	$(info $(TEST_COMPONENTS_LIST))
	$(info $(call dequote,$(SEPARATOR)))
	$(info TEST_EXCLUDE_COMPONENTS (list of test excluded names))
	$(info $(if $(EXCLUDE_COMPONENTS) || $(TEST_EXCLUDE_COMPONENTS),$(EXCLUDE_COMPONENTS) $(TEST_EXCLUDE_COMPONENTS),(none provided)))	
	$(info $(call dequote,$(SEPARATOR)))
	$(info COMPONENT_PATHS (paths to all components):)
	$(foreach cp,$(COMPONENT_PATHS),$(info $(cp)))

# print flash command, so users can dump this to config files and download somewhere without idf
print_flash_cmd: partition_table_get_info blank_ota_data
	echo $(ESPTOOL_WRITE_FLASH_OPTIONS) $(ESPTOOL_ALL_FLASH_ARGS) | sed -e 's:'$(PWD)/build/'::g'

# Check toolchain version using the output of xtensa-esp32-elf-gcc --version command.
# The output normally looks as follows
#     xtensa-esp32-elf-gcc (crosstool-NG crosstool-ng-1.22.0-80-g6c4433a) 5.2.0
# The part in brackets is extracted into TOOLCHAIN_COMMIT_DESC variable
ifdef CONFIG_TOOLPREFIX
ifndef MAKE_RESTARTS

TOOLCHAIN_HEADER := $(shell $(CC) --version | head -1)
TOOLCHAIN_PATH := $(shell which $(CC))
TOOLCHAIN_COMMIT_DESC := $(shell $(CC) --version | sed -E -n 's|.*\(crosstool-NG (.*)\).*|\1|gp')
TOOLCHAIN_GCC_VER := $(COMPILER_VERSION_STR)

# Officially supported version(s)
include $(IDF_PATH)/tools/toolchain_versions.mk

ifndef IS_BOOTLOADER_BUILD
$(info Toolchain path: $(TOOLCHAIN_PATH))
endif

ifdef TOOLCHAIN_COMMIT_DESC
ifeq (,$(findstring $(SUPPORTED_TOOLCHAIN_COMMIT_DESC),$(TOOLCHAIN_COMMIT_DESC)))
$(info WARNING: Toolchain version is not supported: $(TOOLCHAIN_COMMIT_DESC))
$(info Expected to see version: $(SUPPORTED_TOOLCHAIN_COMMIT_DESC))
$(info Please check ESP-IDF setup instructions and update the toolchain, or proceed at your own risk.)
else
ifndef IS_BOOTLOADER_BUILD
$(info Toolchain version: $(TOOLCHAIN_COMMIT_DESC))
endif
endif
ifeq (,$(findstring $(TOOLCHAIN_GCC_VER), $(SUPPORTED_TOOLCHAIN_GCC_VERSIONS)))
$(info WARNING: Compiler version is not supported: $(TOOLCHAIN_GCC_VER))
$(info Expected to see version(s): $(SUPPORTED_TOOLCHAIN_GCC_VERSIONS))
$(info Please check ESP-IDF setup instructions and update the toolchain, or proceed at your own risk.)
else
ifndef IS_BOOTLOADER_BUILD
$(info Compiler version: $(TOOLCHAIN_GCC_VER))
endif
endif
else
$(info WARNING: Failed to find Xtensa toolchain, may need to alter PATH or set one in the configuration menu)
endif # TOOLCHAIN_COMMIT_DESC

endif #MAKE_RESTARTS
endif #CONFIG_TOOLPREFIX


debug:
#	@echo $(COMPILER_VERSION_STR)
	@echo $(COMPONENT_PROJECT_VARS)
