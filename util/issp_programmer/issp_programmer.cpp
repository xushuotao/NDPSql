#include "issp_programmer.h"

bool ISSPProgrammer::devInit = false;

RowSelectorProgramIfcProxy* ISSPProgrammer::program_rowSel   = NULL;
InColProgramIfcProxy*       ISSPProgrammer::program_inCol    = NULL;
ColXFormProgramIfcProxy*    ISSPProgrammer::program_colXform = NULL;
OutColProgramIfcProxy*      ISSPProgrammer::program_outCol   = NULL;



ISSPProgrammer::ISSPProgrammer(){
	init_device();
}



ISSPProgrammer::~ISSPProgrammer(){
	destory_device();
}


void ISSPProgrammer::init_device(){
	if ( !devInit ){
		program_rowSel   = new RowSelectorProgramIfcProxy(IfcNames_RowSelectorProgramIfcS2H);
		program_inCol    = new InColProgramIfcProxy(IfcNames_InColProgramIfcS2H);
		program_colXform = new ColXFormProgramIfcProxy(IfcNames_ColXFormProgramIfcS2H);
		program_outCol   = new OutColProgramIfcProxy(IfcNames_OutColProgramIfcS2H);
	}
}


void ISSPProgrammer::destory_device(){
	if (program_rowSel  ) {free(program_rowSel  ); program_rowSel   = NULL;}
	if (program_inCol   ) {free(program_inCol   ); program_inCol    = NULL;}
	if (program_colXform) {free(program_colXform); program_colXform = NULL;}
	if (program_outCol  ) {free(program_outCol  ); program_outCol   = NULL;}
	devInit = false;
}

uint32_t ISSPProgrammer::encode(DecodeInst inst){
	uint32_t einst = ((uint32_t) inst.iType);
	einst = (einst << 3 )|((uint32_t)inst.inType);
	einst = (einst << 3 )|((uint32_t)inst.outType);
	einst = (einst << 2 )|((uint32_t)inst.aluOp);
	einst = (einst << 1 )|((uint32_t)inst.isSigned);
	einst = (einst << 20)|((uint32_t)inst.imm);
	return einst;
}

void ISSPProgrammer::sendTableTask(TableTask* task){
	// program outCols;
	program_outCol->setColNum(task->numOutCols);
	for ( uint8_t i = 0; i < task->numOutCols; i++ ){
		program_outCol->setParam(i, (task->outCols)[i].param);
	}

	// program colxformPEs;	
	for ( uint8_t i = 0; i < NUM_COLXFORM_PES; i++ ){
		program_colXform->setProgramLength(i, (task->programLength)[i]);
	}

	for ( uint8_t i = 0; i < NUM_COLXFORM_PES; i++ ){
		for ( uint8_t j = 0; j < (task->programLength)[i]; j++){
			program_colXform->setInstruction(encode((task->colXInsts)[i][j]));
		}
	}

	// program inCols;
	program_inCol->setDim(task->numRows, task->numInCols);
	for ( uint8_t i = 0; i < task->numInCols; i++ ){
		program_inCol->setParam(i, (task->inCols)[i].param);
	}

	// program rowSels;
	for ( uint8_t i = 0; i < NUM_SELS; i++ ){
		program_rowSel->setParam(i, (task->rowSels)[i].param);
	}

}
