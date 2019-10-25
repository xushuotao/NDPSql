import Vector::*;

typedef struct {
   Vector#(vSz, iType) d;
   Bool first;
   Bool last;
   } SortedPacket#(numeric type vSz, type iType) deriving (Bits,Eq,FShow);


function Tuple2#(Bool, d) elemFind(Tuple2#(Bool, d) a, Tuple2#(Bool, d) b);
   return tpl_1(a) ? a : b;
endfunction
