/*BEGIN_LEGAL 
Intel Open Source License 

Copyright (c) 2002-2016 Intel Corporation. All rights reserved.
 
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.  Redistributions
in binary form must reproduce the above copyright notice, this list of
conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.  Neither the name of
the Intel Corporation nor the names of its contributors may be used to
endorse or promote products derived from this software without
specific prior written permission.
 
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE INTEL OR
ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
END_LEGAL */
/* ===================================================================== */
// Mark Charney

/* ===================================================================== */
/*! @file
 * This file exemplifies XED usage on IA-32 and Intel(R) 64 architectures.
 */

#include "pin.H"
extern "C" {
#include "xed-interface.h"
}
#include <iostream>
#include <iomanip>
#include <fstream>

#define SHORT_JMP_TO_ITSELF_OFFFSET_OPCODE 0xfeeb  // eb fe = jmp -2 = short jump to itself
#define SIZE_OF_SHORT_JMP_TO_ITSELF_OPCODE 2  // 2 bytes are the size of short jmp -2 to itself

#define LONG_JMP_TO_ITSELF_OFFFSET_OPCODE 0x000000fffffffbe9  // e9 fb ff ff ff  = jmp -5 = long jump to itself
#define SIZE_OF_LONG_JMP_TO_ITSELF_OPCODE 5  // 5 bytes are the size of long jmp -5 to itself


/* ===================================================================== */
/* Global Variables */
/* ===================================================================== */
std::ofstream* out = 0;

/* ===================================================================== */
/* Commandline Switches */
/* ===================================================================== */


/* ===================================================================== */
/* Print Help Message                                                    */
/* ===================================================================== */

INT32 Usage()
{
    cerr << "This tool prints IA-32 and Intel(R) 64 instructions"
         << endl;
    cerr << KNOB_BASE::StringKnobSummary();
    cerr << endl;
    return -1;
}

/* ===================================================================== */

VOID use_xed(ADDRINT pc) {
#if defined(TARGET_IA32E)
    static const xed_state_t dstate = {XED_MACHINE_MODE_LONG_64, XED_ADDRESS_WIDTH_64b};
#else
    static const xed_state_t dstate = { XED_MACHINE_MODE_LEGACY_32, XED_ADDRESS_WIDTH_32b};
#endif
    xed_decoded_inst_t xedd;
    xed_decoded_inst_zero_set_mode(&xedd,&dstate);

    //Pass in the proper length: 15 is the max. But if you do not want to
    //cross pages, you can pass less than 15 bytes, of course, the
    //instruction might not decode if not enough bytes are provided.
    const unsigned int max_inst_len = 15;

	// direct long jump to itself 
	// e9 fb ff ff ff  = jmp -5
	//char mem[5];
	//mem[0] = 0xe9;   // jmp -5 = long jmp to itself (5 bytes long)
	//mem[1] = 0xfb;
	//mem[2] = 0xff;
	//mem[3] = 0xff;
	//mem[4] = 0xff;

	// direct short jump to itself:
	// eb fe = jmp -2 
    //char mem[2];
	//mem[0] = 0xeb;   // jmp -2 = short jmp to itself (2 bytes long)
	//mem[1] = 0xfe;
	
	ADDRINT memory = SHORT_JMP_TO_ITSELF_OFFFSET_OPCODE;  // short jump to itself
	ADDRINT *mem = &memory;

    xed_error_enum_t xed_code = xed_decode(&xedd, reinterpret_cast<UINT8*>(mem), max_inst_len);
    BOOL xed_ok = (xed_code == XED_ERROR_NONE);
    if (xed_ok) {
        *out << hex << std::setw(8) << pc << " ";
        char buf[2048];

        // set the runtime adddress for disassembly 
        xed_uint64_t runtime_address = static_cast<xed_uint64_t>(pc); 

        xed_format_context(XED_SYNTAX_INTEL, &xedd,
                           buf, 2048, runtime_address, 0, 0);
        *out << buf << endl;
    }

}

/* ===================================================================== */

VOID Instruction(INS ins, VOID *v)
{
    INS_InsertCall(ins, IPOINT_BEFORE, (AFUNPTR)use_xed, 
                   IARG_INST_PTR,
                   IARG_END);
}

/* ===================================================================== */


/* ===================================================================== */
/* Main                                                                  */
/* ===================================================================== */

int main(int argc, char *argv[])
{
    out = new std::ofstream("xed-print.out");
    if( PIN_Init(argc,argv) )
        return Usage();
    INS_AddInstrumentFunction(Instruction, 0);
    PIN_StartProgram();    // Never returns
    return 0;
}

/* ===================================================================== */
/* eof */
/* ===================================================================== */