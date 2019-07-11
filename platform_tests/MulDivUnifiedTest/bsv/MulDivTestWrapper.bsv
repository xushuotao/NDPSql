
import MulDivTestRequest::*;
import MulDivTestIndication::*;

import Clocks::*;

// import UserClkRst::*;
import MulDivTestIF::*;
import MulDivTest::*;

interface MulDivTestWrapper;
    interface MulDivTestRequest request;
endinterface

module mkMulDivTestWrapper#(MulDivTestIndication indication)(MulDivTestWrapper);
    Clock portalClk <- exposeCurrentClock;
    Reset portalRst <- exposeCurrentReset;

// `ifndef BSIM
//     // user clock
//     UserClkRst userClkRst <- mkUserClkRst(`USER_CLK_PERIOD);
//     Clock userClk = userClkRst.clk;
//     Reset userRst = userClkRst.rst;
// `else
//     Clock userClk = portalClk;
//     Reset userRst = portalRst;
// `endif

    MulDivTest test <- mkMulDivTest;

    rule doResp;
        let r <- test.resp;
        indication.resp(r);
    endrule

    interface MulDivTestRequest request;
        method setTest = test.setTest;
    endinterface
endmodule
