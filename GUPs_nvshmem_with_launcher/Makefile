#
#
# OpenSHMEM version:
#
# Copyright (c) 2011 - 2015
#   University of Houston System and UT-Battelle, LLC.
#
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# o Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
#
# o Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the distribution.
#
# o Neither the name of the University of Houston System,
#   UT-Battelle, LLC. nor the names of its contributors may be used to
#   endorse or promote products derived from this software without specific
#   prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

#
# OpenSHMEM compiler commandss
#
CC             = /home/app/nvhpc/24.11/Linux_x86_64/24.11/compilers/bin/nvcc
LD             = $(CC)

CFLAGS         = -O3

NVSHMEM_HOME = /home/app/nvhpc/24.11/Linux_x86_64/24.11/comm_libs/12.6/nvshmem
NVSHMEM_INC = $(NVSHMEM_HOME)/include
NVSHMEM_LIB = $(NVSHMEM_HOME)/lib
#
# any extra paths/flags needed
#
SHMEM_INC_PATH = -I/home/app/gcc/8/ompi/4.1.6/include -I$(NVSHMEM_INC) 
SHMEM_LDFLAGS  = -L/home/app/gcc/8/ompi/4.1.6/lib -L$(NVSHMEM_LIB) 
SHMEM_LIBS     = -loshmem -lnvshmem

CPPFLAGS       = -I./include $(SHMEM_INC_PATH)
LDFLAGS        = $(CFLAGS) $(SHMEM_LDFLAGS)
LIBS           = $(SHMEM_LIBS) -lm

TARGET         = gups.out

SOURCES        = SHMEMRandomAccess.cu
OBJECTS        = $(SOURCES:.cu=.o) 

.PHONY:	all	clean

# 在这里添加 GPU 架构标志
NVCCFLAGS     = -arch=sm_70

%.o: %.cu
	$(CC) $(NVCCFLAGS) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

#
# make starts here
#

all:  $(TARGET)

$(TARGET): $(OBJECTS) 
	$(LD) $(LDFLAGS) $^ -o $@ $(LIBS)

clean:
	rm -f $(OBJECTS) $(TARGET)


#
# object/header deps
#

SHMEMRandomAccess.o:	RandomAccess.h

