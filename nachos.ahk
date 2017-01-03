/* 	Patient List Updater (C)2016 TC
	NACHOS = The Networked Aggregator for Consulting Hospitals and Outpatient Services
*/

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
Clipboard = 	; Empty the clipboard
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetTitleMatchMode, 2
SetWorkingDir %A_ScriptDir% ; Ensures a consistent starting directory.
#Include Includes
#Persistent		; Keep program resident until ExitApp

vers := "2.0.7"
user := A_UserName
FormatTime, sessdate, A_Now, yyyyMM
WinClose, View Downloads -
LV_Colors.OnMessage()

;FileInstall, pscp.exe, pscp.exe								; Necessary files (?)

;gosub ReadIni

scr:=screenDims()
win:=winDim(scr)

servfold := "patlist"
chipotlePath := "\\childrens\files\HCChipotle"
storkPath := "\\childrens\files\HCCardiologyFiles\Fetal"
forecastPath := "\\childrens\files\HCSchedules\Electronic Forecast"
if (InStr(A_WorkingDir,"Ahk")) {
	tmp:=CMsgBox("Data source","Data from which system?","&Local|&Test Server|Production","Q","V")
	if (tmp="Local") {
		isLocal := true
		;FileDelete, currlist.xml
		storkPath := "files\Fetal"
		forecastPath := "files\Electronic Forecast"
	}
	if (tmp="Test Server") {
		isLocal := false
		servfold := "testlist"
		;FileDelete, currlist.xml
	}
	if (tmp="Production") {
		isLocal := false
		;FileDelete, currlist.xml
	}
}
if (ObjHasValue(admins,user)) {
	isAdmin := true
}

Docs := Object()
outGrps := []
outGrpV := {}
tmpIdxG := 0
Loop, Read, outdocs.csv
{
	tmp := tmp0 := tmp1 := tmp2 := tmp3 := tmp4 := ""
	tmpline := A_LoopReadLine
	StringSplit, tmp, tmpline, `, , `"
	if ((tmp1="Name") or (tmp1="end")) {
		continue
	}
	if (tmp1) {
		if (tmp2="" and tmp3="" and tmp4="") {							; Fields 2,3,4 blank = new group
			tmpGrp := tmp1
			tmpIdx := 0
			tmpIdxG += 1
			outGrps.Insert(tmpGrp)
			continue
		} else if (tmp4="group") {										; Field4 "group" = synonym for group name
			tmpIdx += 1													; if including names, place at END of group list to avoid premature match
			Docs[tmpGrp,tmpIdx]:=tmp1
			outGrpV[tmpGrp] := "callGrp" . tmpIdxG
		} else {														; Otherwise format Crd name to first initial, last name
			tmpIdx += 1
			StringSplit, tmpPrv, tmp1, %A_Space%`"
			tmpPrv := substr(tmpPrv1,1,1) . ". " . tmpPrv2
			Docs[tmpGrp,tmpIdx]:=tmpPrv
			outGrpV[tmpGrp] := "callGrp" . tmpIdxG
		}
	}
}
outGrpV["Other"] := "callGrp" . (tmpIdxG+1)
outGrpV["TO CALL"] := "callGrp" . (tmpIdxG+2)

SetTimer, SeekWordErr, 250

initDone = true
eventlog(">>>>> Session started.")
Gosub GetIt
;~ Gosub MainGUI
WinWaitClose, NACHOS main
;~ Gosub SaveIt
eventlog("<<<<< Session completed.")
ExitApp


;	===========================================================================================
;~ #Include getini.ahk
;	===========================================================================================

SeekWordErr:
{
if (Word_win2 := WinExist("User Name")) {
	ControlSend,, {Enter}, ahk_id %Word_win2%
	;MsgBox,,Win 2, %Word_win2%
	return
}
If (Word_win1 := WinExist("Microsoft Office Word", "The command cannot be performed because a dialog box is open.")) {
	ControlSend,, {Esc}, ahk_id %Word_win1%
	;MsgBox,,Win 1, %Word_win1%
	return
}
Return
}

initClipSub:									;*** Initialize XML files
{
	if !IsObject(t:=y.selectSingleNode("//root")) {		; if Y is empty,
		y.addElement("root")					; then create it.
		y.addElement("lists", "root")			; space for some lists
	}
	FormatTime, timenow, A_Now, yyyyMMddHHmm

	Return
}

Sort2D(Byref TDArray, KeyName, Order=1) {
/*	modified from https://sites.google.com/site/ahkref/custom-functions/sort2darray	
	TDArray : a two dimensional TDArray
	KeyName : the key name to be sorted
	Order: 1:Ascending 0:Descending
*/
	For index2, obj2 in TDArray {           
		For index, obj in TDArray {
			if (lastIndex = index)
				break
			if !(A_Index = 1) && ((Order=1) ? (TDArray[prevIndex][KeyName] > TDArray[index][KeyName]) : (TDArray[prevIndex][KeyName] < TDArray[index][KeyName])) {    
			   tmp := TDArray[index]
			   TDArray[index] := TDArray[prevIndex]
			   TDArray[prevIndex] := tmp  
			}         
			prevIndex := index
		}     
		lastIndex := prevIndex
	}
}

filecheck() {
	if FileExist(".currlock") {
		err=0
		Progress, , Waiting to clear lock, File write queued...
		loop 50 {
			if (FileExist(".currlock")) {
				progress, %p%
				Sleep 100
				p += 2
			} else {
				err=1
				break
			}
		}
		if !(err) {
			progress off
			return error
		}
	} 
	progress off
	return
}

refreshCurr(lock:="") {
/*	Refresh Y in memory with currlist.xml to reflect changes from other users.
	If invalid XML, try to read the most recent .bak file in reverse chron order.
	If all .bak files fail, get last saved server copy.
	If lock="", filecheck()/currlock is handled from outside this function.
	If lock=1, will handle the filecheck()/currlock within this call.
*/
	global y
	if (lock) {
		filecheck()
		FileOpen(".currlock", "W")												; Create lock file
	}
	if (z:=checkXML("stork.xml")) {											; Valid XML
		y := new XML(z)														; <== Is this valid?
		if (lock) 
			FileDelete, .currlock													; Clear the file lock
		return																	; Return with refreshed Y
	}
	
	eventlog("*** Failed to read currlist. Attempting backup restore.")
	dirlist :=
	Loop, files, bak\*.bak
	{
		dirlist .= A_LoopFileTimeCreated "`t" A_LoopFileName "`n"				; build up dirlist with Created time `t Filename
	}
	Sort, dirlist, R															; Sort in reverse chron order
	Loop, parse, dirlist, `n
	{
		name := strX(A_LoopField,"`t",1,1,"",0)									; Get filename between TAB and NL
		if (z:=checkXML("bak\" name)) {											; Is valid XML
			y := new XML(z)														; Replace Y with Z
			eventlog("Successful restore from " name)
			FileCopy, bak\%name%, stork.xml, 1								; Replace currlist.xml with good copy
			if (lock)
				FileDelete, .currlock											; Clear file lock
			return
		} else {
			FileDelete, bak\%name%												; Delete the bad bak file
		}
	}
	
	eventlog("** Failed to restore backup.")
	;~ sz := httpComm("full")														; call download of FULL list from server, not just changes
	;~ FileDelete, templist.xml
	;~ FileAppend, %sz%, templist.xml												; write out as templist
	;~ if (z:=checkXML("templist.xml")) {
		;~ y := new XML(z)															; Replace Y with Z
		;~ eventlog("Successful restore from server.")
		;~ filecopy, templist.xml, currlist.xml, 1									; copy templist to currlist
		;~ if (lock)
			;~ FileDelete, .currlock													; clear file lock
		;~ return
	;~ }
	
	;~ eventlog("*** Failed to restore from server.")									; All attempts fail. Something bad has happened.
	;~ httpComm("err999")															; Pushover message of utter failure
	FileDelete, .currlock
	MsgBox, 16, CRITICAL ERROR, Unable to read currlist. `n`nExiting.
	ExitApp
}

checkXML(xml) {
/*	Simple integrity check for XML files.
	Reads XML file into string, checks if string ends with </root>
	If success, returns obj. If not, returns error.
 */
	FileRead, str, % xml	
	Loop, parse, str, `n, `r
	{
		test := A_LoopField
		if !(test) {
			continue
		}
		lastline := test
	}
	if instr(lastline,"</root>") {
		if (pos:=RegExMatch(str,"[^[:ascii:]]")) {
			per := instr(str,"<id",,pos-strlen(str))
			RegExMatch(str,"O)<\w+((\s+\w+(\s*=\s*(?:"".*?""|'.*?'|[\^'"">\s]+))?)+\s*|\s*)/?>",pre,per)
			RegExMatch(str,"O)</\w+\s*[\^>]*>",post,pos)
			eventlog("Illegal chars detected in " xml " in " pre.value "/" post.value ".")
			str := RegExReplace(str,"[^[:ascii:]]","~")
		}
		return str
	} else {
		return error 
	}
}

GetIt:
{
	; ==================															; temporarily delete this when testing to avoid delays.
	;FileDelete, .currlock
	; ==================
	filecheck()																		; delay loop if .currlock set (currlist write in process)
	FileOpen(".currlock", "W")														; Create lock file.
	if !(vSaveIt=true)																; not launched from SaveIt:
		Progress, b w300, Reading data..., % "- = C H I P O T L E = -`nversion " vers "`n"
			;. "`n`nNow with " rand(20,99) "% less E. coli!"									; This could be a space for a random message
	else
		Progress, b w300, Consolidating data..., 
	Progress, 20																	; launched from SaveIt, no CHIPOTLE header

	Progress, 30, % dialogVals[Rand(dialogVals.MaxIndex())] "..."
	refreshCurr()																	; Get currlist, bak, or server copy
	eventlog("Valid currlist.")
	
	Progress, 80, % dialogVals[Rand(dialogVals.MaxIndex())] "..."
	if !(isLocal) {																	; live run, download changes file from server
		;~ ckRes := httpComm("get")													; Check response from "get"
		
		;~ if (ckRes=="NONE") {														; no change.xml file present
			;~ eventlog("No change file.")
		;~ } else if (instr(ckRes,"proxy")) {											; hospital proxy problem
			;~ eventlog("Hospital proxy problem.")
		;~ } else {																	; actual response, merge the blob
			;~ eventlog("Import blob found.")
			;~ StringReplace, ckRes, ckRes, `r`n,`n, All								; MSXML cannot handle the UNIX format when modified on server 
			;~ StringReplace, ckRes, ckRes, `n,`r`n, All								; so convert all MS CRLF to Unix LF, then all LF back to CRLF
			;~ z := new XML(ckRes)														; Z is the imported updates blob
			
			;~ importNodes()															; parse Z blob
			;~ eventlog("Import complete.")
			
			;~ if (WriteFile()) {														; Write updated Y to currlist
				;~ eventlog("Successful currlist update.")
				;~ ckRes := httpComm("unlink")											; Send command to delete update blob
				;~ eventlog((ckRes="unlink") ? "Changefile unlinked." : "Not unlinked.")
			;~ } else {
				;~ eventlog("*** httpComm failed to write currlist.")
			;~ }
		;~ }
	}

	Progress 100, % dialogVals[Rand(dialogVals.MaxIndex())] "..."
	Sleep 500
	Progress, off
	FileDelete, .currlock
Return
}

readStorkList:
{
/*	Directly read a Stork List XLS.
	Sheets
		(1) is "Potential cCHD"
		(2) is "Neonatal echo and Regional Cons"
		(3) is archives
	
*/
	storkPath := A_WorkingDir "\files\stork.xls"
	if !FileExist(storkPath) {
		MsgBox None!
		return
	}
	if IsObject(y.selectSingleNode("/root/lists/stork")) {
		RemoveNode("/root/lists/stork")
	}
	y.addElement("stork","/root/lists"), {date:timenow}
		
	storkPath := A_WorkingDir "\files\stork.xls"
	oWorkbook := ComObjGet(storkPath)
	colArr := ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q"] ;array of column letters
	stork_hdr := Object()
	stork_cel := Object()
	Loop 
	{
		RowNum := A_Index
		chk := oWorkbook.Sheets(1).Range("A" RowNum).value
		if (RowNum=1) {
			upDate := chk
			continue
		}
		if !(chk)
			break
		Progress,,% rownum, Scanning Stork List
		Loop
		{	
			ColNum := A_Index
			if (colnum>maxcol)
				maxcol:=colnum
			cel := oWorkbook.Sheets(1).Range(colArr[ColNum] RowNum).value
			if ((cel="") && (colnum=maxcol))
				break
			if (rownum=2) {
				if (cel~="Mother's Name") {
					cel:="Names"
				}
				if (cel~="Mother.*SCH.*#") {
					cel:="Mother SCH"
				}
				if (cel~="Mother.*\sU.*#") {
					cel:="Mother UW"
				}
				if (cel~="Planned.*del.*date") {
					cel:="Planned date"
				}
				if (cel~="i)Most.*Recent.*Consult") {
					cel:="Recent dates"
				}
				if (cel~="i)cord.*blood") {
					cel:="Cord blood"
				}
				if (cel~="i)care.*plan.*ORCA") {
					cel:="Orca plan"
				}
				if (cel~="i)Continuity.*Cardio") {
					cel:="CRD"
				}
				stork_hdr[ColNum] := trim(cel)
			} else {
				stork_cel[ColNum] := cel
			}
		}
		stork_mrn := Round(stork_cel[ObjHasValue(stork_hdr,"Mother SCH")])
		if !(stork_mrn)
			continue
		y.addElement("id","/root/lists/stork",{mrn:stork_mrn})
		stork_str := "/root/lists/stork/id[@mrn='" stork_mrn "']"
		
		stork_names := stork_cel[ObjHasValue(stork_hdr,"Names")]
		if (instr(stork_names,",",,,2)) {												; A second "," means baby name present
			pos2 := RegExMatch(stork_names,"i)(?<=\s)[a-z\-\/]+,",,instr(stork_names,",",,,1))
			name2 := trim(substr(stork_names,pos2))
			name1 := trim(substr(stork_names,1,pos2-1))
			y.addElement("mother", stork_str)
				y.addElement("nameL", stork_str "/mother", trim(strX(name1,,0,0,", ",1,2)))
				y.addElement("nameF", stork_str "/mother", trim(strX(name1,", ",0,2)))
			y.addElement("baby", stork_str)
				y.addElement("nameL", stork_str "/baby", trim(strX(name2,,0,0,", ",1,2)))
				y.addElement("nameF", stork_str "/baby", trim(strX(name2,", ",0,2)))
		} else {
			y.addElement("mother", stork_str)
				y.addElement("nameL", stork_str "/mother", trim(strX(stork_names,,0,0,", ",1,2)))
				y.addElement("nameF", stork_str "/mother", trim(strX(stork_names,", ",0,2)))
		}
		
		stork_uw := stork_cel[ObjHasValue(stork_hdr,"Mother UW")]
		if (stork_uw)
			y.addElement("UW", stork_str "/mother", stork_uw)
		
		stork_home := stork_cel[ObjHasValue(stork_hdr,"Home")]
		y.addElement("home", stork_str "/mother", stork_home)
		
		stork_hosp := stork_cel[ObjHasValue(stork_hdr,"Delivery Hosp")]
		y.addElement("birth", stork_str)
		y.addElement("hosp", stork_str "/birth", stork_hosp)
		
		stork_edc := stork_cel[ObjHasValue(stork_hdr,"EDC")]
		y.addElement("edc", stork_str "/birth", stork_edc)
		
		stork_del := stork_cel[ObjHasValue(stork_hdr,"Planned date")]
		if (stork_del) {
			tmp := RegExMatch(stork_del,"\d")
			y.addElement("mode", stork_str "/birth", trim(substr(stork_del,1,tmp-1)))
			y.addElement("planned", stork_str "/birth", trim(substr(stork_del,tmp)))
		}
		
		stork_dx := stork_cel[ObjHasValue(stork_hdr,"Diagnosis")]
		y.addElement("dx", stork_str "/baby", stork_dx)
		
		stork_notes := stork_cel[ObjHasValue(stork_hdr,"Comments")]
		if (stork_notes)
			y.addElement("notes", stork_str "/baby", stork_notes)
		
		y.addElement("prov", stork_str)
		
		stork_cont := stork_cel[ObjHasValue(stork_hdr,"CRD")]
		if (stork_cont)
			y.addElement("cont", stork_str "/prov", stork_cont)
		
		stork_prv := trim(cleanSpace(stork_cel[ObjHasValue(stork_hdr,"Recent dates")]))
		nn := 0
		While (stork_prv) 
		{
			stork_prov := parsePnProv(stork_prv)
			y.addElement(stork_prov.svc, stork_str "/prov", {date:stork_prov.date}, stork_prov.prov)
		}
		
		stork_cord := stork_cel[ObjHasValue(stork_hdr,"Cord blood")]
		if (stork_cord)
			y.addElement("cord", stork_str "/birth", stork_cord)
		
		stork_orca := stork_cel[ObjHasValue(stork_hdr,"Orca Plan")]
		if (stork_orca)
			y.addElement("orca", stork_str "/birth", stork_orca)
		
	}
	Progress, Hide

	oExcel := oWorkbook.Application
	oExcel.quit

	MsgBox Stork List updated.
	Writeout("/root/lists","stork")
	Eventlog("Stork List updated.")
Return
}

WriteOut(path,node) {
/* 
	Prevents concurrent writing of y.MRN data. If someone is saving data (.currlock exists), script will wait
	approx 6 secs and check every 50 msec whether the lock file is removed. When available it creates clones the y.MRN
	node, loads a fresh currlist into Z (latest update), replaces the z.MRN node with the cloned y.MRN node,
	saves it, then reloads this currlist into Y.
*/
	global y
	filecheck()
	FileOpen(".currlock", "W")													; Create lock file.
	locPath := y.selectSingleNode(path)
	locNode := locPath.selectSingleNode(node)
	clone := locNode.cloneNode(true)											; make copy of y.node
	
	if (ck:=checkXML("stork.xml")) {											; Valid XML
		z := new XML(ck)
	} else {
		eventlog("*** WriteOut failed to read currlist.")
		dirlist :=
		Loop, files, bak\*.bak
		{
			dirlist .= A_LoopFileTimeCreated "`t" A_LoopFileName "`n"			; build up dirlist with Created time `t Filename
		}
		Sort, dirlist, R														; Sort in reverse chron order
		Loop, parse, dirlist, `n
		{
			name := strX(A_LoopField,"`t",1,1,"",0)								; Get filename between TAB and NL
			if (ck:=checkXML("bak\" name)) {									; Is valid XML
				z := new XML(ck)												; Replace Y with Z
				eventlog("WriteOut restore Z from " name)
				FileCopy, bak\%name%, stork.xml, 1							; Replace currlist.xml with good copy
				break
			} else {
				FileDelete, bak\%name%											; Delete the bad bak file
			}
		}											
	}																			; temp Z will be most recent good currlist
	
	if !IsObject(z.selectSingleNode(path "/" node)) {
		If instr(node,"id[@mrn") {
			z.addElement("id","root",{mrn: strX(node,"='",1,2,"']",1,2)})
		} else {
			z.addElement(node,path)
		}
	}
	zPath := z.selectSingleNode(path)											; find same "node" in z
	zNode := zPath.selectSingleNode(node)
	zPath.replaceChild(clone,zNode)												; replace existing zNode with node clone
	
	z.save("stork.xml")														; write z into currlist
	FileCopy, stork.xml, % "bak/" A_now ".bak"								; create a backup for each writeout
	
	y := z																		; make Y match Z, don't need a file op
	FileDelete, .currlock														; release lock file.
	return
}

PatNode(mrn,path,node) {
	global y
	return y.selectSingleNode("/root/id[@mrn='" mrn "']/" path "/" node)
}

ReplacePatNode(path,node,value) {
	global y
	if (k := y.selectSingleNode(path "/" node)) {	; Node exists, even if empty.
		y.setText(path "/" node, value)
	} else {
		y.addElement(node, path, value)
	}
}

RemoveNode(node) {
	global
	local q
	q := y.selectSingleNode(node)
	q.parentNode.removeChild(q)
}

ObjHasValue(aObj, aValue, rx:="") {
; modified from http://www.autohotkey.com/board/topic/84006-ahk-l-containshasvalue-method/	
	if (rx="med") {
		med := true
	}
    for key, val in aObj
		if (rx) {
			if (med) {													; if a med regex, preface with "i)" to make case insensitive search
				val := "i)" val
			}
			if (aValue ~= val) {
				return, key, Errorlevel := 0
			}
		} else {
			if (val = aValue) {
				return, key, ErrorLevel := 0
			}
		}
    return, false, errorlevel := 1
}

breakDate(x) {
; Disassembles 201502150831 into Yr=2015 Mo=02 Da=15 Hr=08 Min=31 Sec=00
	D_Yr := substr(x,1,4)
	D_Mo := substr(x,5,2)
	D_Da := substr(x,7,2)
	D_Hr := substr(x,9,2)
	D_Min := substr(x,11,2)
	D_Sec := substr(x,13,2)
	FormatTime, D_day, x, ddd
	return {"YYYY":D_Yr, "MM":D_Mo, "DD":D_Da, "ddd":D_day
		, "HH":D_Hr, "min":D_Min, "sec":D_sec}
}

parseDate(x) {
; Disassembles "2/9/2015" or "2/9/2015 8:31" into Yr=2015 Mo=02 Da=09 Hr=08 Min=31
	StringSplit, DT, x, %A_Space%
	StringSplit, DY, DT1, /
	;~ if !(DY0=3) {
		;~ ;MsgBox Wrong date format!
		;~ return
	;~ }
	StringSplit, DHM, DT2, :
	return {"MM":zDigit(DY1), "DD":zDigit(DY2), "YYYY":DY3, "hr":zDigit(DHM1), "min":zDigit(DHM2), "Date":DT1, "Time":DT2}
}

Rand( a=0.0, b=1 ) {
/*	from VxE http://www.autohotkey.com/board/topic/50564-why-no-built-in-random-function-in-ahk/?p=315957
	Rand() ; - A random float between 0.0 and 1.0 (many uses)
	Rand(6) ; - A random integer between 1 and 6 (die roll)
	Rand("") ; - New random seed (selected randomly)
	Rand("", 12345) ; - New random seed (set explicitly)
	Rand(50, 100) ; - Random integer between 50 and 100 (typical use)
*/
	IfEqual,a,,Random,,% r := b = 1 ? Rand(0,0xFFFFFFFF) : b
	Else Random,r,a,b
	Return r
}

niceDate(x) {
	if !(x)
		return error
	FormatTime, x, %x%, MM/dd/yyyy
	return x
}

zDigit(x) {
; Add leading zero to a number
	return SubStr("0" . x, -1)
}

cleanString(x) {
	replace := {"{":"[", "}":"]", "\":"/"
				,"ñ":"n"}
	for what, with in replace
	{
		StringReplace, x, x, %what%, %with%, All
	}
	x := RegExReplace(x,"[^[:ascii:]]")									; filter unprintable (esc) chars
	return x
}

cleanspace(ByRef txt) {
	StringReplace txt,txt,`n,%A_Space%, All
	StringReplace txt,txt,%A_Space%.%A_Space%,.%A_Space%, All
	loop
	{
		StringReplace txt,txt,%A_Space%%A_Space%,%A_Space%, UseErrorLevel
		if ErrorLevel = 0	
			break
	}
	return txt
}

cleanwhitespace(txt) {
	Loop, Parse, txt, `n, `r
	{
		if (A_LoopField ~= "i)[a-z]+") {
			nxt .= A_LoopField "`n"
		}
	}
	return nxt
}

screenDims() {
	W := A_ScreenWidth
	H := A_ScreenHeight
	DPI := A_ScreenDPI
	Orient := (W>H)?"L":"P"
	;MsgBox % "W: "W "`nH: "H "`nDPI: "DPI
	return {W:W, H:H, DPI:DPI, OR:Orient}
}
winDim(scr) {
	global ccFields
	num := ccFields.MaxIndex()
	if (scr.or="L") {
		aspect := (scr.W/scr.H >= 1.5) ? "W" : "N"	; 1.50-1.75 probable 16:9 aspect, 1.25-1.33 probable 4:3 aspect
		;MsgBox,, % aspect, % W/H
		wX := scr.H * ((aspect="W") ? 1.5 : 1)
		wY := scr.H-80
		rCol := wX*.3						; R column is 1/3 width
		bor := 10
		boxWf := wX-rCol-2*bor				; box fullwidth is remaining 2/3
		boxWh := boxWf/2
		boxWq := boxWf/4
		rH := 12
		demo_h := rH*8
		butn_h := rh*6
		cont_h := wY-demo_H-bor-butn_h
		field_h := (cont_h-20)/num
	} else {
		wX := scr.W
		wY := scr.H
	}
	return { BOR:Bor, wX:wX, wY:wY
		,	boxF:boxWf
		,	boxH:boxWh
		,	boxQ:boxWq
		,	demo_H:demo_H
		,	cont_H:cont_H
		,	field_H:field_H
		,	rCol:rCol
		,	rH:rH}
}

eventlog(event) {
	global user, sessdate
	comp := A_ComputerName
	FormatTime, now, A_Now, yyyy.MM.dd||HH:mm:ss
	name := "logs/" . sessdate . ".log"
	txt := now " [" user "/" comp "] " event "`n"
	filePrepend(txt,name)
;	FileAppend, % timenow " ["  user "/" comp "] " event "`n", % "logs/" . sessdate . ".log"
}

FilePrepend( Text, Filename ) { 
/*	from haichen http://www.autohotkey.com/board/topic/80342-fileprependa-insert-text-at-begin-of-file-ansi-text/?p=510640
*/
    file:= FileOpen(Filename, "rw")
    text .= File.Read()
    file.pos:=0
    File.Write(text)
    File.Close()
}



;~ #Include gui-main.ahk
;~ #Include gui-CallList.ahk
;~ #Include gui-TeamList.ahk
;~ #Include gui-PatList.ahk
;~ #Include gui-PatListCC.ahk
;~ #Include gui-plNotes.ahk
;~ #Include gui-Tasks.ahk
;~ #Include gui-plData.ahk
;~ #Include gui-cards.ahk
;~ #Include process.ahk
;~ #Include io.ahk
;~ #Include labs.ahk
;~ #Include meds.ahk
;~ #Include print.ahk

#Include xml.ahk
#Include StrX.ahk
#Include StRegX.ahk
#Include Class_LV_Colors.ahk
#Include sift3.ahk
#Include CMsgBox.ahk