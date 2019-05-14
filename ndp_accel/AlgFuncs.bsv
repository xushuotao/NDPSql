function Bit#(w) add2(Bit#(w) a, Bit#(w) b);
   return a + b;
endfunction

function Bit#(w) and2(Bit#(w) a, Bit#(w) b);
   return a&b;
endfunction

function Bool booland2(Bool a, Bool b);
   return a&&b;
endfunction

function Bit#(w) or2(Bit#(w) a, Bit#(w) b);
   return a|b;
endfunction

function Bit#(w) maxUnsigned2(Bit#(w) a, Bit#(w) b);
   return a > b ? a : b; 
endfunction

function Bit#(w) minUnsigned2(Bit#(w) a, Bit#(w) b);
   return a < b ? a : b; 
endfunction


function Bit#(w) maxSigned2(Bit#(w) a, Bit#(w) b);
   return signedGT(a,b) ? a : b; 
endfunction

function Bit#(w) minSigned2(Bit#(w) a, Bit#(w) b);
   return signedLT(a,b) ? a : b; 
endfunction

