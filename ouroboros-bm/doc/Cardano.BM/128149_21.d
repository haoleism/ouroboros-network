format 221

classinstance 128021 class_ref 128405 // Controller
 name ""  xyz 374 232 2000
classinstance 128149 class_ref 128021 // Trace
 name ""  xyz 290 364 2000
classinstancecanvas 128277 classinstance_ref 128021 // User
  xyz 105 364 2000
end
classinstance 128661 class_ref 129941 // TraceContext
 name ""  xyz 628 229 2000
note 129813 "entering a log item : LogItem, the  Trace will check the minimumSeverity in the TraceContext, and the named severity filter, if available."
  xyzwh 80 113 2000 325 89
classinstance 129941 class_ref 130197 // LoggerName
 name ""  xyz 484 369 2000
linkcanvas 128405
  from ref 128277 z 2001 to ref 128149
dirscanvas 129045 z 1000 linkcanvas_ref 128405
  
  forward_label "1 logInfo()" xyz 203 345 3000
linkcanvas 128533
  from ref 128149 z 2001 to ref 128021
dirscanvas 128917 z 1000 linkcanvas_ref 128533
  
  forward_label "2 checkSeverity()" xyz 275 280 3000
linkcanvas 128789
  from ref 128021 z 2001 to ref 128661
dirscanvas 129429 z 1000 linkcanvas_ref 128789
  
  forward_label "2.1 minimumSeverity()
2.2 namedSeverityFilter()" xyz 460 194 3000
linkcanvas 130069
  from ref 128149 z 2001 to ref 129941
dirscanvas 130197 z 1000 linkcanvas_ref 130069
  
  forward_label "3 view()" xyz 258 375 3000
msgs
  msg operation_ref 129301 // "logInfo()"
    forward ranks 1 "1" dirscanvas_ref 129045
    no_msg
  msg operation_ref 129429 // "checkSeverity()"
    forward ranks 2 "2" dirscanvas_ref 128917
    msgs
      msg operation_ref 129557 // "minimumSeverity()"
	forward ranks 3 "2.1" dirscanvas_ref 129429
	no_msg
      msg operation_ref 129685 // "namedSeverityFilter()"
	forward ranks 4 "2.2" dirscanvas_ref 129429
	no_msg
    msgsend
  msg operation_ref 136853 // "view()"
    forward ranks 5 "3" dirscanvas_ref 130197
    no_msg
msgsend
end