format 221

classinstance 128021 class_ref 129173 // EKGView
 name ""  xyz 547 164 2000
classinstance 128533 class_ref 128405 // Controller
 name ""  xyz 365 233 2000
classinstancecanvas 128661 classinstance_ref 128021 // User
  xyz 130 234 2000
end
classinstance 128789 class_ref 128021 // Trace
 name ""  xyz 275 284 2000
linkcanvas 128917
  from ref 128661 z 2001 to ref 128533
dirscanvas 129045 z 1000 linkcanvas_ref 128917
  
  forward_label "1 createEKGTrace()" xyz 222 214 3000
linkcanvas 129173
  from ref 128533 z 2001 to ref 128789
dirscanvas 129557 z 1000 linkcanvas_ref 129173
  
linkcanvas 129301
  from ref 128533 z 2001 to ref 128021
dirscanvas 129429 z 1000 linkcanvas_ref 129301
  
  forward_label "2 setup()
3 createLabel()" xyz 428 165 3000
msgs
  msg operation_ref 136341 // "createEKGTrace()"
    forward ranks 1 "1" dirscanvas_ref 129045
    msgs
      msg operation_ref 136213 // "setup()"
	forward ranks 2 "1.1" dirscanvas_ref 129429
	no_msg
    msgsend
  msg operation_ref 136469 // "createLabel()"
    forward ranks 3 "2" dirscanvas_ref 129429
    no_msg
msgsend
end