unit PosBankUnit;

interface

uses
  Forms, SysUtils, Windows, Classes, Dialogs, Definition;

  procedure SetUnionpayRoute;
  function LanDiSetCommMode(MsgStr: String): String;
  function LanDiGetCommMode: String;
  function getLandiCardno(Track2, Track3: PChar): Boolean;
  function doNormal(mode: ShortInt; flag: String): Boolean;
  function ProWalletCard(r: PayItem; tot, index : Integer): Boolean;
  function ProCreditCard(r: PayItem; tot, index : Integer): Boolean;
  function OnBankSettle: Boolean;

implementation

uses BaseUnit, MsgUnit, DesUnit, PosBaseUnit,PosFileUnit, PosClassUnit;

//浙江银联-BASE

procedure SetLR(Str: String; Flag: Integer = 0);
var
  FOutStrA: array of string;
  len: Integer;
begin
  FillChar(gLR, Sizeof(gLR), Char(0));

  FOutStrA := nil;
  case Flag of
    0:
    begin
      try
        SetLength(FOutStrA, getCharCount(Str, Char($1C)) + 1);
        StrToArrayS(Str, Char($1C), FOutStrA);
        len := Length(FOutStrA);
        if len > 0 then gLR.Instruction := FOutStrA[0];
        if len > 1 then gLR.Code := FOutStrA[1];
        if len > 2 then gLR.Hint := FOutStrA[2];
        if len > 3 then gLR.Cardno := FOutStrA[3];
        if len > 4 then gLR.CheckSum := FOutStrA[4];
        if len > 5 then gLR.Amount := FOutStrA[5];
        if len > 6 then gLR.BankCode := FOutStrA[6];
      except
      end;
    end;
    1:
    begin

    end;
    2:
    begin
      gLR.Instruction := '';
      gLR.Code := '';
      gLR.Hint := Str;
    end;
    3:
    begin
      gLR.Code := Copy(Str, 82, 2)
    end;
  end;
end;

function ChinaUnion(Packet: String; var Ret: Integer): String;
var
  Sock: TMySocket;
  SockHead: array[0..1] of Char;
  SendPacketA,RecvPacketA: array[0..65536] of Char;   //64K ISO8583 128域
  i,len,unionlen: Integer;
begin
  Result := '';
  Ret := 0;

  //把包转成字符数组
  for i := 1 to Length(Packet) do SendPacketA[i - 1] := Packet[i];
  Sock := TMySocket.Create(cuBankSrv, Str2Int(cuBankSrvPort), 500, true);
  //建立socket短连接
  try
    try
      if Sock.FConnect then
      begin
        len := Sock.Write(@SendPacketA, Length(Packet));

        if len = Length(Packet) then
        begin
          if Sock.WaitFor(60000, 0) then //等待超时60秒
          begin
            if Sock.Read(@SockHead, 2) = 2 then
            begin
              unionlen := Byte(SockHead[0]) * 256 + Byte(SockHead[1]);
              if Sock.Read(@RecvPacketA,unionlen) = unionlen then
              begin
                for i := 1 to unionlen do Result := Result + RecvPacketA[i - 1];
              end
              else
              begin
                Ret := -5;
                SetLR('与银联通讯失败,请检查网络是否正常!', 2);
              end;
            end
            else
            begin
              Ret := -4;
              SetLR('与银联通讯失败,请检查网络是否正常!', 2);
            end;
          end
          else
          begin
            Ret := -3;
            SetLR('发卡方无应答!', 2);
          end;
        end
        else
        begin
          Ret := -2;
          SetLR('与银联通讯失败,请检查网络是否正常!', 2);
        end;
      end
      else
      begin
        Ret := -1;
        SetLR('与银联通讯失败,请检查网络是否正常!', 2);
      end;
    except
      Ret := -6;
      SetLR('与银联通讯失败,请检查网络是否正常!', 2);
    end;
  finally
    Sock.Free;
  end;
end;

function Pack(InPath, InType: Byte; InCont: string; InID: string = LanDiId): string;  //封装通信结构
var
  lSTX,lETX,LEN0,LEN1,lPATH,lTYPE: Char;
  lLEN,lID,lCont,Temp,TempOutStr: String;
  LRC: Byte;
begin
  lSTX := Char($02); //报文起始

  LEN0 := Char((8 + Length(InCont)) div 256);
  LEN1 := Char((8 + Length(InCont)) mod 256);
  lLEN := LEN0+LEN1;

  lPATH := Char(InPath);
  lTYPE := Char(InType);

  lID := InID;
  lCont := InCont;

  lETX := Char($03); //报文终止

  Temp := lLEN + lPATH + lTYPE + lID + lCONT + lETX;
  TempOutStr := Temp;
  while Length(Temp) > 1 do
  begin
    LRC := Byte(Temp[1]) xor Byte(Temp[2]);
    Temp := Char(LRC) + Copy(Temp, 3, Length(Temp) - 2);
  end;
  TempOutStr := lSTX + TempOutStr + Temp;
  Result := TempOutStr;
end;

function UnPack(InType: Byte; var OutRet: Integer; var ChinaUnionFlag: Boolean; InID: string = LanDiId; TimeOut: Integer = 180000): String;
var
  lSTX,LEN0,LEN1,lPATH,lTYPE,lETX,lLRC: Char;
  Temp,lsCont: String;
  llCont,i,Outlen: Integer;
  lID: array[0..5] of Char;
  LRC: Byte;
  laCont: array[0..65536] of Char;
begin
  Result := '';
  LRC := Ord(0);
  OutRet := -1;  //修正异常返回码为-1, 2010.07.19
  SetLR('未知错误!', 2);

  ChinaUnionFlag := false;

  //接受消息包
  PinCom.Recv(lSTX, 1, TimeOut);
  if lSTX = Char($02) then
  begin
    PinCom.Recv(LEN0, 1, 1000);
    PinCom.Recv(LEN1, 1, 1000);
    //处理长度
    llCont := Byte(LEN0) * 256 + Byte(LEN1) - 8; //正文长度
    Outlen := llCont;   //modify 2010.03.08 修正包长度
    //处理数据流向属性
    PinCom.Recv(lPATH, 1, 1000);
    //处理应用类型
    PinCom.Recv(lTYPE, 1, 1000);
    //处理唯一标识
    PinCom.Recv(lID, 6, 1000);

    if (lTYPE = Char(InType)) and (lID = InID) then
    begin
      PinCom.Recv(laCont, llCont, 60000);
      for i := 1 to llCont do lsCont := lsCont + laCont[i - 1];

      PinCom.Recv(lETX, 1, 1000);

      if lETX = Char($03) then
      begin
        lLRC := lLRC;
        PinCom.Recv(lLRC, 1, 1000);
        Temp := LEN0 + LEN1 + lPATH + lTYPE + lID + lsCONT + lETX;
        while Length(Temp) > 1 do
        begin
          LRC := Byte(Temp[1]) xor Byte(Temp[2]);
          Temp := Char(LRC) + Copy(Temp, 3, Length(Temp) - 2);
        end;

        if lLRC = Char(LRC) then
        begin
          SetLR(''); //初始化
          if lPath = Char($05) then //向中心请求包
          begin
            ChinaUnionFlag := true; //置银联标记
            Result := Hex2Str(IntToHex(Outlen, 4)) + lsCont; //8583包加上长度包头
          end
          else
          begin
            if (lPath = Char($02)) or (lPath = Char($04)) then  //测试应答包或收银应答包
            begin
              if (lsCont[1] = Char($06)) or (lsCont[1] = Char($15)) then
                SetLR(lsCont);
            end;
            Result := lsCont;
          end;
          OutRet := 0;  // 成功返回码
        end
        else
        begin
          OutRet := -4;
          SetLR('校验MISPOS设备通信结构LRC失败,请检查设备是否正常!', 2);
        end;
      end
      else
      begin
        OutRet := -3;
        SetLR('读取MISPOS设备报文终止值失败,请检查设备是否正常连接!', 2);
      end;
    end
    else
    begin
      OutRet := -2;
      SetLR('读取MISPOS设备通信结构ID失败,请检查设备是否正常!', 2);
    end;
  end
  else
  begin
    OutRet := -5;
    SetLR('读取MISPOS设备报文起始值失败,请检查设备是否正常连接!', 2);
  end;
end;

procedure SetUnionpayRoute;
var
  Lv_Type,Lv_Result,Lv_ResultStr: String;
begin
  P_CreditPort := Pub_BankPort;
  Lv_Result := LanDiGetCommMode;
  if Lv_Result = 'P' then
    Lv_ResultStr := '电话线路'
  else if Lv_Result = 'G' then
    Lv_ResultStr := '主机线路'
  else if Lv_Result = 'R' then
    Lv_ResultStr := 'GPRS';
  if (Lv_Result = 'P') or (Lv_Result = 'R') or (Lv_Result = 'G') then
  begin
    if ShowInputQuery('【★★★ ' + '银联线路切换' + ' ★★★】', '当前通讯方式：' + Lv_ResultStr + '请输入新类别（0：电话线路；1：主机线路；2：GPRS）', 0, 0, Lv_Type) then
    begin
      if Lv_Type = '0' then
      begin
        Lv_ResultStr := '电话线路';
        Lv_Result := LanDiSetCommMode('P');
      end
      else if Lv_Type = '1' then
      begin
        Lv_ResultStr := '主机线路';
        Lv_Result := LanDiSetCommMode('R');
      end
      else if Lv_Type = '2' then
      begin
        Lv_ResultStr := 'GPRS';
        Lv_Result := LanDiSetCommMode('G');
      end
      else
      begin
        Lv_ResultStr := '';
        Lv_Result := '交易失败';
      end;
      if Lv_Result = '交易成功' then
        ShowMessageBox('成功切换至' + Lv_ResultStr + '刷卡模式', '消息', MB_OK + MB_ICONINFORMATION)
      else
        ShowMessageBox('银联线路切换失败', '消息', MB_OK + MB_ICONINFORMATION);
    end;
  end
  else
    ShowMessageBox('线路状态获取失败', '系统消息', MB_ICONWARNING);
end;

//浙江银联-PRINT

procedure PrintBankCoupon2(rs: resPos);

  //取括号内外内容
  function getBrackets(InStr: string; Mode: String): string;
  var
    i: Integer;
    Temp: string;
    FoundBegin: Boolean;
  begin
    Result := InStr;
    FoundBegin := false;
    Temp := '';
    if Mode = 'Y' then //括号内
    begin
      for i := 1 to Length(InStr) do
      begin
        if InStr[i] = '[' then
        begin
          FoundBegin := true;
          Continue;
        end;
        if InStr[i] = ']' then
          Break;
        if not FoundBegin then
          Continue
        else
          Temp := Temp + InStr[i];
      end;
      Result := Temp;
    end
    else if Mode = 'N' then
    begin
      for i := 1 to Length(InStr) do
      begin
        if InStr[i] = '[' then
        begin
          FoundBegin := true;
          Continue;
        end;
        if InStr[i] = ']' then
        begin
          FoundBegin := false;
          Continue;
        end;
        if FoundBegin then
          Continue
        else
          Temp := Temp + InStr[i];
      end;
      Result := Temp;
    end;
  end;

var
  f: textfile;
  bankfile,fmt0,fmt1,fmt2,fmt3,sCouponCode,sTime: String;
  i: integer;
begin
  bankfile := 'BANKCOUPON.1';
  fmt0 := '%-31s';
  fmt1 := '%8s: %-22s';
  fmt2 := '%8s: %-6s %8s:%6s';
  fmt3 := '%8s: %-24s';

  if f_empstr(gBankMemo) or f_empstr(getBrackets(gBankMemo, 'Y')) then Exit;
  sTime := FormatDateTime('hh:mm:ss', now);

  AssignFile(f, g_path + bankfile);
  ReWrite(f);
  Writeln(f, GetMemo('周五周六就刷62银联卡'));
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));

  Writeln(f, StrCenter(format(fmt0, ['恭喜您中奖'+ getBrackets(gBankMemo, 'Y') + '元券!'])));
  Writeln(f, StrCenter(format(fmt1, ['商户名称', p_Company])));
  Writeln(f, StrCenter(format(fmt1, ['商户编号', cuMerchantID])));
  Writeln(f, StrCenter(format(fmt1, ['终端编号', format('%8.8s', [cuTerminalID])])));
  Writeln(f, StrCenter(format(fmt1, ['刷卡卡号', rs.Cardno])));
  Writeln(f, StrCenter(format(fmt1, ['发 卡 行', gCard])));
  Writeln(f, StrCenter(format(fmt1, ['中奖时间', rs.date + rs.time])));
  Writeln(f, StrCenter(format(fmt1, ['参 考 号', gRefno])));
  Writeln(f, StrCenter(format(fmt0, [format('%8s: %-12.2f', ['交易金额', strtofloat(rs.amount) / 100])])));

  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt0, ['持卡人签名:'])));
  for i := 0 to 1 do Writeln(f, '');
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt0, ['本人已确认领兑奖券'])));
  Writeln(f, '');
  //
  Writeln(f, '');
  Writeln(f, StrCenter(sline));
  Writeln(f, '   小票号: ' + Days + P_Syjh + P_seqno + '  时间:' + sTime);
  Writeln(f, '   您获得的');
  Writeln(f, '[INTIME1001]    电子券: ￥' + getBrackets(gBankMemo, 'Y'));
  Writeln(f, '   使用有效期:' + getDateTime('4', '') + '止');
  Writeln(f, '   特例商品,辅营业种恕不接受,详见专柜明示');
  Writeln(f, '   本券恕不兑换现金,不找零');
  Writeln(f, '   限' + p_Company + '使用,自行撕下无效');
  //
  sCouponCode := SetCouponInfo('YL', '0', '电子券', '4', sTime, rs.Cardno, rs.BankCode, gRefno, '', '', '', strtofloat(rs.amount) / 100, Str2Float(getBrackets(gBankMemo, 'Y')), 1);
  if sCouponCode <> '' then
    Writeln(f, '[INTIME9802]' + sCouponCode);
  Writeln(f, StrCenter(sline));
  Writeln(f, '');
  Writeln(f, '[INTIME9901]');

  Flush(f);
  CloseFile(f);

  DoPrint(g_path + bankfile, 1, false);
end;


procedure PrintBankPaper(rq: reqPos; rs: resPos; tot: Integer; rePrint: String);
var
  f: textfile;
  fmt0,fmt1,fmt2,fmt3: String;
  rctfile,bankfile: array[0..11] of Char;
  i: integer;
  FOutStrA: array of string;
begin
  FOutStrA := nil;
  bankfile := 'BANKRCT.';
  fmt0 := '%-31s';
  fmt1 := '%8s: %-22s';
  fmt2 := '%8s: %-6s %8s:%6s';
  fmt3 := '%8s: %-24s';
  StrCopy(rctfile, Pchar(format('%s%-03d', [bankfile, tot])));
  AssignFile(f, g_path + rctfile);
  ReWrite(f);
  if cuType = $05 then
    Writeln(f, GetMemo('手机支付签购单'))
  else
    Writeln(f, GetMemo(P_BankTitle));
  if rePrint = 'Y' then
    Writeln(f, StrCenter('【重打印】'));
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt1, ['商户名称', p_Company])));
  Writeln(f, StrCenter(format(fmt1, ['商户编号', cuMerchantID])));
  if P_BankType <> '12' then
    Writeln(f, StrCenter(format(fmt1, ['终端编号', format('%8.8s', [cuTerminalID])])));
  if IsPaperSMode then
    Writeln(f, StrCenter(ssline))
  else
    Writeln(f, StrCenter(sline));
  Writeln(f, '   ' + format(fmt3, ['卡    号', rs.Cardno]));

  Writeln(f, StrCenter(format(fmt1, ['发 卡 行', gCard]))); //银联新标准
  if rs.LandiType = '01' then
    Writeln(f, StrCenter(format(fmt2, ['交易类型', '消费', '有 效 期', gExpdate])))
  else if rs.LandiType = '02' then
    Writeln(f, StrCenter(format(fmt2, ['交易类型', '撤消', '有 效 期', gExpdate])))
  else if rs.LandiType = '03' then
    Writeln(f, StrCenter(format(fmt2, ['交易类型', '退货', '有 效 期', gExpdate])))
  else if rs.LandiType = '42' then
    Writeln(f, StrCenter(format(fmt2, ['交易类型', '撤消', '有 效 期', gExpdate])))
  else if rs.LandiType = '43' then
    Writeln(f, StrCenter(format(fmt2, ['交易类型', '退货', '有 效 期', gExpdate])))
  else
    Writeln(f, StrCenter(format(fmt2, ['交易类型', '其他', '有 效 期', gExpdate])));
  Writeln(f, StrCenter(format(fmt2, ['交易日期', rs.date, '交易时间', rs.time])));
  Writeln(f, StrCenter(format(fmt2, ['批 次 号', rs.batchno, '中心流水', rs.invoice])));

  Writeln(f, StrCenter(format(fmt1, ['商户流水', gRefno])));
  Writeln(f, StrCenter(format(fmt1, ['授 权 号', rs.authno])));

  Writeln(f, StrCenter(format(fmt0, [format('%-9s: %-7s', ['MIS交易号', P_Syjh + P_Seqno])])));
  //银联钱包判断
  if (Trim(rs.WalletType) <> '') and (req.SaleType = 1) then
    Writeln(f, StrCenter(format(fmt0, [format('%8s: %-12.2f', ['交易金额', strtofloat(rs.amount) / 100 + strtofloat(rs.WalletAmt) / 100])])))
  else
    Writeln(f, StrCenter(format(fmt0, [format('%8s: %-12.2f', ['交易金额', strtofloat(rs.amount) / 100])])));

  Writeln(f, StrCenter(format(fmt0, ['持卡人身份证号码:'])));
  if rq.Cardid[0] <> '0' then Writeln(f, StrCenter(format(fmt0, [rq.cardid])));
  if not f_empstr(gBankMemo) then
  begin
    SetLength(FOutStrA, getCharCount(gBankMemo, ';') + 1);
    StrToArrayS(gBankMemo, ';', FOutStrA);
    Writeln(f, '   备注: ');
    for i := 0 to High(FOutStrA) do
    begin
      if not f_empstr(FOutStrA[i]) then Writeln(f, '   ' + trim(FOutStrA[i]));
    end;
  end;
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt0, ['持卡人签名:'])));
  for i := 0 to 1 do Writeln(f, '');
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt0, ['本人同意支付上述款项'])));
  Writeln(f, '');
  Writeln(f, '[INTIME9901]');
  Flush(f);
  CloseFile(f);

  if FileExists(g_path + P_BankPaper) then
  begin
    if P_BankPaperPrint <> 'N' then
    begin
      for i := 1 to StrtoInt(P_BankPaperCount) do
        DoPrint(g_path + P_BankPaper, 1, false);
    end;
  end
  else if FileExists(P_BankPaper) then
  begin
    if P_BankPaperPrint <> 'N' then
    begin
      for i := 1 to StrtoInt(P_BankPaperCount) do
        DoPrint(P_BankPaper, 1, false);
    end;
  end
  else
    ShowMessageBox('信用卡签购单文件 [' + P_BankPaper + '] 不存在,请联系信息部!', '系统警告', MB_ICONSTOP);
end;

procedure PrintBankSettlePaper;   //信用卡结算单
var
  f: TextFile;
  title: string;
  fmt,fmt0,fmt1,fmt2,fmt3: String;
begin
  fmt0 := '%-31s';
  fmt1 := '%8s: %-22s';
  fmt2 := '%8s: %-12.2f';
  fmt3 := '%8s: %-12d';

  fmt :=  '%8s:%-10s%8s:%-12s';

  AssignFile(f,g_path + 'BANKSETTLE.1');

  ReWrite(f);

  if cuType = $05 then
    title := '手机支付结算单'
  else
    title := '银联商户结算单';
  Writeln(f, GetMemo(title));
  Writeln(f, '[INTIME9800]');
  Writeln(f, '');
  Writeln(f, getSpace + '日期:' + getLocalDate + ' 时间:' + FormatDateTime('hh:mm:ss', now));
  if IsPaperSMode then
    Writeln(f, StrCenter(ssline))
  else
    Writeln(f, StrCenter(sline));
  Writeln(f, getSpace + format(fmt1, ['商户名称', gBankSettle.MchtName]));
  Writeln(f, getSpace + format(fmt1, ['商户编号', gBankSettle.MchtCode]));
  Writeln(f, getSpace + format(fmt1, ['终端编号', gBankSettle.TermId]));
  Writeln(f, getSpace + format(fmt1, ['操作员号', P_gh]));
  Writeln(f, getSpace + format(fmt1, ['批 次 号', gBankSettle.Batchno]));
  if IsPaperSMode then
    Writeln(f, StrCenter(ssline))
  else
    Writeln(f, StrCenter(sline));
  Writeln(f, getSpace + format(fmt3, ['消费笔数', Str2Int(gBankSettle.Inbs1)]));
  Writeln(f, getSpace + format(fmt2, ['消费金额', Str2Float(gBankSettle.Inje1) / 100]));
  Writeln(f, getSpace + format(fmt3, ['退货笔数', Str2Int(gBankSettle.Inbs2)]));
  Writeln(f, getSpace + format(fmt2, ['退货金额', Str2Float(gBankSettle.Inje2) / 100]));
  if IsPaperSMode then
    Writeln(f, StrCenter(ssline))
  else
    Writeln(f, StrCenter(sline));
  Writeln(f, getSpace + format(fmt2, ['金额总计', (Str2Float(gBankSettle.Inje1) - Str2Float(gBankSettle.Inje2)) / 100]));
  Writeln(f, '');
  Writeln(f, '[INTIME9901]');
  Flush(f);
  CloseFile(f);

  DoPrint(g_path + 'BANKSETTLE.1', 1, false);
end;

function getLandiPrintmsg(isprint, reprint: Boolean): Boolean;
var
  lSendCont,Send,Recv: String;
  ret,i: Integer;
  CUF: Boolean;
  FBankCode: array[0..5] of char;
  FOutStrA: array of string;
begin
  Result := false;
  FOutStrA := nil;
  gBankMemo := '';

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //打印信息
    if reprint then
      lSendCont := '61' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + Char($1C) + Char($1C) + '000000' + Char($1C) + '1'
    else
      lSendCont := '61' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + Char($1C) + Char($1C) + '000000' + Char($1C) + '0';
    Send := Pack($03, cuType, lSendCont);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF);

    if ret = 0 then
    begin
      try
        SetLength(FOutStrA, getCharCount(Recv, Char($1C)) + 1);
        StrToArrayS(Recv, Char($1C), FOutStrA);
        res.RspCode := '00';
        for i := 0 to High(FOutStrA) do
        begin
          FOutStrA[i] := Trim(FOutStrA[i]);
          case i of
            6:
            begin
              StrToArray(res.Bankcode, FOutStrA[i]); //发卡银行名称
              StrToArray(FBankCode, Copy(FOutStrA[i], 1, 4));
              getTransStr(PChar(g_Path + 'Banks.ini'), FBankCode, gCard);
            end;
            8: StrToArray(res.Cardno, FOutStrA[i]); //卡号
            10: StrToArray(res.LandiType, FOutStrA[i]); //设备交易类型
            11: StrToArray(gExpdate, FOutStrA[i]); //卡有效日期
            12: StrToArray(res.Batchno, FOutStrA[i]); //批次号
            13: StrToArray(res.Invoice, FOutStrA[i]); //流水号
            14:
            begin
              StrToArray(res.Date, Copy(FOutStrA[i], 1, 4)); //交易日期
              StrToArray(res.Time, Copy(FOutStrA[i], 5, 6)); //交易时间
            end;
            15: StrToArray(res.Authno, FOutStrA[i]); //授权号
            16: StrToArray(gRefno, FOutStrA[i]); //参考号
            17: StrToArray(res.Amount, FOutStrA[i]); //交易金额，元为单位，小数点2位
            33:  //备注
            begin
              if (not f_empstr(FOutStrA[i])) and (P_SaleType = '0') then
              begin
                StrToArray(gBankMemo, FOutStrA[i]);
              end;
            end;
            34: StrToArray(res.CheckSum, FOutStrA[i]); //校验码
            41: StrToArray(res.WalletType, FOutStrA[i]); //银联钱包交易类型
            42: StrToArray(res.WalletAmt, FOutStrA[i]); //银联钱包交易金额
            43: StrToArray(res.WalletSerial, FOutStrA[i]); //银联钱包流水号
            44: StrToArray(res.WalletRef, FOutStrA[i]); //银联钱包参考号
          end;
          Result := true;
        end;
        if isprint and (FOutStrA[1] <> 'Y1') and (Pub_BankPaper <> '1') then
          PrintBankPaper(req, res, 1, 'Y');
      except
      end;
    end
    else
    begin
      ShowMessageBox(gLR.Hint, '信用卡提示', MB_ICONWARNING);
    end;
  finally
    PinCom.Free;
  end;
end;

function getLandiPrintmsgExt(Recv: String): Boolean;
var
  i: Integer;
  FBankCode: array[0..5] of char;
  FOutStrA: array of string;
begin
  Result := false;
  FOutStrA := nil;
  gBankMemo := '';

  try
    SetLength(FOutStrA, getCharCount(Recv, Char($1C)) + 1);
    StrToArrayS(Recv, Char($1C), FOutStrA);

    res.RspCode := '00';
    for i := 0 to High(FOutStrA) do
    begin
      FOutStrA[i] := Trim(FOutStrA[i]);
      case i of
        6 + 3:
        begin
          StrToArray(res.Bankcode, FOutStrA[i]); //发卡银行名称
          StrToArray(FBankCode, Copy(FOutStrA[i], 1, 4));
          getTransStr(PChar(g_Path + 'Banks.ini'), FBankCode, gCard);
        end;
        8 + 3: StrToArray(res.Cardno, FOutStrA[i]); //卡号
        10 + 3: StrToArray(res.LandiType, FOutStrA[i]); //设备交易类型
        11 + 3: StrToArray(gExpdate, FOutStrA[i]); //卡有效日期
        12 + 3: StrToArray(res.Batchno, FOutStrA[i]); //批次号
        13 + 3: StrToArray(res.Invoice, FOutStrA[i]); //流水号
        14 + 3:
        begin
          StrToArray(res.Date, Copy(FOutStrA[i], 1, 4)); //交易日期
          StrToArray(res.Time, Copy(FOutStrA[i], 5, 6)); //交易时间
          end;
        15 + 3: StrToArray(res.Authno, FOutStrA[i]); //授权号
        16 + 3: StrToArray(gRefno, FOutStrA[i]); //参考号
        17 + 3: StrToArray(res.Amount, FOutStrA[i]); //交易金额，元为单位，小数点2位
        33 + 3:  //备注
        begin
          if (not f_empstr(FOutStrA[i])) and (P_SaleType = '0') then
          begin
            StrToArray(gBankMemo, FOutStrA[i]);
          end;
        end;
        34 + 3: StrToArray(res.CheckSum, FOutStrA[i]); //校验码
        41 + 3: StrToArray(res.WalletType, FOutStrA[i]); //银联钱包交易类型
        42 + 3: StrToArray(res.WalletAmt, FOutStrA[i]); //银联钱包交易金额
        43 + 3: StrToArray(res.WalletSerial, FOutStrA[i]); //银联钱包流水号
        44 + 3: StrToArray(res.WalletRef, FOutStrA[i]); //银联钱包参考号
      end;
      Result := true;
    end;
  except
  end;
end;

procedure SetBankTradeInfo(Flag: Integer = -1);
begin
  FillChar(BankTradeInfo, Sizeof(BankTradeInfo), Char(0));
  case Flag of
    -1 :
    begin
      StrToArray(BankTradeInfo.Cardno, res.Cardno);     //卡号
      StrToArray(BankTradeInfo.DateTime, FormatDateTime('yyyy', now) + StrPas(res.Date) + StrPas(res.Time)); //日期时间
      if Trim(BankTradeInfo.DateTime) = FormatDateTime('yyyy', now) then
      begin
        StrToArray(BankTradeInfo.DateTime, FormatDateTime('yyyymmddhhmmss', now));
      end;
      StrToArray(BankTradeInfo.BankCode, res.BankCode); //银行号
      StrToArray(BankTradeInfo.BankName, gCard);        //银行名称
      StrToArray(BankTradeInfo.Amount, res.Amount);     //金额
      StrToArray(BankTradeInfo.PosTrace, res.Invoice);  //中心流水
      StrToArray(BankTradeInfo.Batchno, res.Batchno);   //批次号
      StrToArray(BankTradeInfo.Mode, IntToStr(req.SaleType)); //交易类型
      StrToArray(BankTradeInfo.RspCode, res.RspCode);   //应答码
      StrToArray(BankTradeInfo.RefNum, gRefno);         //参考号
      StrToArray(BankTradeInfo.CheckSum, res.CheckSum); //校验码
      if (Trim(res.WalletType) <> '') and ((req.SaleType = 2) or (req.SaleType = 6)) then
        StrToArray(BankTradeInfo.CommMode, res.WalletType)
      else
        StrToArray(BankTradeInfo.CommMode, '00');     //银联钱包类别
      if not f_empstr(gBankMemo) then //备注
      begin
        StrToArray(BankTradeInfo.Memo, gBankMemo);
      end;
    end;
    10:
    begin
      StrToArray(BankTradeInfo.DateTime, FormatDateTime('yyyymmddhhmmss', now));
      StrToArray(BankTradeInfo.RspCode, gLR.Code);
      StrToArray(BankTradeInfo.RspName, gLR.Hint);
      StrToArray(BankTradeInfo.Cardno, gLR.Cardno);
      StrToArray(BankTradeInfo.CheckSum, gLR.CheckSum);
      StrToArray(BankTradeInfo.Amount, gLR.Amount);     //金额
      StrToArray(BankTradeInfo.BankCode, gLR.BankCode); //银行号
      StrToArray(BankTradeInfo.Mode, gLR.Mode); //交易类型
    end;
  end;

  StrToArray(BankTradeInfo.TermId, cuTerminalID);  //终端号
  StrToArray(BankTradeInfo.MchtCode, cuMerchantID);  //商户号
  StrToArray(BankTradeInfo.Fphm, P_syjh + P_seqno);  //小票号码
  StrToArray(BankTradeInfo.Syyh, IntToStr(High(PayA) + 1));  //支付方式行号
  StrToArray(BankTradeInfo.Storeno, g_Store);  //分店店号
  StrToArray(BankTradeInfo.Opertime, FormatDateTime('yyyymmddhhmmss', now)); //操作时间

  //针对卡号和校验码为空情况特殊处理
  if f_empstr(BankTradeInfo.Cardno) then
  begin
    StrToArray(BankTradeInfo.Cardno, '000000******0000');
    StrToArray(BankTradeInfo.CheckSum, 'B02132081808B493C61E86626EE6C2E29326A662');
  end;

  BankTradeInfo.Flag := '0';
  AppendDosRecord(@BankTradeInfo, 11);

  //银联钱包处理
  if (Trim(res.WalletType) <> '') and (req.SaleType = 1) then
  begin
    StrToArray(BankTradeInfo.CommMode, res.WalletType);
    StrToArray(BankTradeInfo.Amount, res.WalletAmt);
    StrToArray(BankTradeInfo.PosTrace, res.WalletSerial);
    StrToArray(BankTradeInfo.RefNum, res.WalletRef);
    StrToArray(BankTradeInfo.Opertime, FormatDateTime('yyyymmddhhmmss', now + 1 / 24 / 60 / 60));
    AppendDosRecord(@BankTradeInfo, 11);
  end;
end;

function getLandiSettlemsg: Boolean;   //获得结算信息
var
  lSendCont,Send,Recv: String;
  ret,i: Integer;
  CUF: Boolean;
  FOutStrA: array of string;
begin
  Result := false;
  FOutStrA := nil;
  FillChar(gBankSettle, Sizeof(gBankSettle), Char(0));

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //结算信息
    lSendCont := '62' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C);
    Send := Pack($03, cuType, lSendCont);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF);

    if ret = 0 then
    begin
      try
        SetLength(FOutStrA, getCharCount(Recv, Char($1C)) + 1);
        StrToArrayS(Recv, Char($1C), FOutStrA);

        for i := 0 to High(FOutStrA) do
        begin
          FOutStrA[i] := Trim(FOutStrA[i]);
          case i of
            1: gBankSettle.MchtCode := FOutStrA[i];  //商户代码
            2: gBankSettle.TermId := FOutStrA[i];    //终端号
            3: gBankSettle.MchtName := FOutStrA[i];  //商户名称
            5: gBankSettle.Batchno := FOutStrA[i];   //批次号
            6: gBankSettle.DateTime := FOutStrA[i];  //日期时间
            8: gBankSettle.Inbs1 := FOutStrA[i];     //消费笔数
            9: gBankSettle.Inje1 := FOutStrA[i];     //消费金额
            10: gBankSettle.Inbs2 := FOutStrA[i];     //退货笔数
            11: gBankSettle.Inje2 := FOutStrA[i];     //退货金额
          end;
          Result := true;
        end;
      except
      end;
    end
  else
  begin
    ShowMessageBox(gLR.Hint, '信用卡提示', MB_ICONWARNING);
  end;
  finally
    PinCom.Free;
  end;
end;

//浙江银联-FUNC

function LanDiTest: Boolean; //测试连接报文
var
  Send,Recv,lID,lSendCont: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  ret := -1;
  lID := FormatDateTime('hhmmss', now);

  if cuType = $05 then  //手机支付
  begin
    Result := true;
    Exit;
  end;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    lSendCont := '99';
    Send := Pack($03,cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID, 2000);

    if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then Result := true;
  finally
    PinCom.Free;
  end;

  if Result then gLR.Hint := ''; //清变量
end;

function LandiPartial: Boolean;  //分期付款
var
  lSendCont,Send,Recv,lID: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  req.Mode := '0';
  ret := -1;
  lID := FormatDateTime('hhmmss', now);
  //
  req.SaleType := 7;

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    lSendCont := '12' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C) + Char($1C) + req.Amount + Char($1C) + Char($1C) + Char($1C) + gBankPrint;
    Send := Pack($03, cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret = 0 then
      begin
        Send := Pack($06, cuType, lSendCont, lID);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF, lID);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
        begin
          getLandiPrintmsgExt(Recv);
          Result := true;
        end;
      end
      else
        Recv := UnPack(cuType, ret, CUF, lID);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
    begin
      getLandiPrintmsgExt(Recv);
      req.Mode := '1';
      Result := true;
    end;
  finally
    if not Result then
    begin
      gLR.Mode := '7';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function LandiConsume: Boolean;
var
  lSendCont,Send,Recv,lID: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  req.Mode := '0';
  ret := -1;
  lID := FormatDateTime('hhmmss', now);

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //消费
    lSendCont := '01' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C) + Char($1C) + req.Amount + Char($1C) + gBankPrint;
    Send := Pack($03, cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret = 0 then
      begin
        Send := Pack($06, cuType, lSendCont, lID);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF, lID);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
        begin
          getLandiPrintmsgExt(Recv);
          Result := true;
        end;
      end
      else
        Recv := UnPack(cuType, ret, CUF, lID);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
    begin
      getLandiPrintmsgExt(Recv);
      req.Mode := '1';
      Result := true;
    end;
  finally
    if not Result then
    begin
      gLR.Mode := '1';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function LandiRepeal: Boolean;    //撤消
var
  lSendCont,Send,Recv,lID: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  req.Mode := '0';
  ret := -1;
  lID := FormatDateTime('hhmmss', now);

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //消费撤消
    lSendCont := '02' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C) + Char($1C) + req.Amount + Char($1C) + gInvoice + Char($1C) + gBankPrint;
    Send := Pack($03, cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret = 0 then
      begin
        Send := Pack($06, cuType, lSendCont, lID);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF, lID);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
        begin
          getLandiPrintmsgExt(Recv);
          Result := true;
        end;
      end
      else
        Recv := UnPack(cuType, ret, CUF, lID);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
    begin
      getLandiPrintmsgExt(Recv);
      req.Mode := '1';
      Result := true;
    end;
  finally
    if not Result then
    begin
      gLR.Mode := '2';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function LandiRecall: Boolean;    //隔日退货
var
  lSendCont,Send,Recv,lID: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  req.Mode := '0';
  ret := -1;
  lID := FormatDateTime('hhmmss', now);
  //
  req.SaleType := 6; //隔日退货

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //退货
    lSendCont := '03' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C) + Char($1C) + req.Amount + Char($1C) + Char($1C) + Char($1C) + gBankPrint;
    Send := Pack($03, cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret = 0 then
      begin
        Send := Pack($06, cuType, lSendCont, lID);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF, lID);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
        begin
          getLandiPrintmsgExt(Recv);
          Result := true;
        end;
      end
      else
        Recv := UnPack(cuType, ret, CUF, lID);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
    begin
      getLandiPrintmsgExt(Recv);
      req.Mode := '1';
      Result := true;
    end;
  finally
    if not Result then
    begin
      gLR.Mode := '6';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function LandiInquiry: Boolean;
var
  lSendCont,Send,Recv,lID: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  req.Mode := '0';
  ret := -1;
  lID := FormatDateTime('hhmmss', now);

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //余额查询
    lSendCont := '04' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C);
    Send := Pack($03, cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret = 0 then
      begin
        Send := Pack($06, cuType, lSendCont, lID);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF, lID);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
        begin
          getLandiPrintmsgExt(Recv);
          Result := true;
        end;
      end
      else
        Recv := UnPack(cuType, ret, CUF, lID);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
    begin
      getLandiPrintmsgExt(Recv);
      req.Mode := '1';
      Result := true;
    end;
  finally
    if not Result then
    begin
      gLR.Mode := '1';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function LandiSettle: Boolean; //结算
var
  lSendCont,Send,Recv: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    lSendCont := '52' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C) + Char($1C) + gBankPrint;
    Send := Pack($03, cuType, lSendCont);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret=0 then
      begin
        Send := Pack($06, cuType, lSendCont);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then Result := true;
      end
      else
        Recv := UnPack(cuType, ret, CUF);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then Result := true;

  finally
    if not Result then
    begin
      gLR.Mode := '3';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function LanDiGetCommMode: String; //获取联迪键盘通讯模式 G:GPRS P:电话
var
  Send,Recv: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := '0';
  if gCommMode = '1' then
  begin
    try
      PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

      Send := Pack($03, $01, 'A3');
      PinCom.PutStrA(Send);
      Recv := UnPack($01, ret, CUF);

      if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then Result := gLR.Hint;
    finally
      PinCom.Free;
    end;
  end;
end;

function LanDiSetCommMode(MsgStr: String): String; //改变联迪键盘通讯模式 G:GPRS P:电话
var
  Send,Recv,lSendCont: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := '';
  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    lSendCont := 'A2' + Char($1C) + MsgStr;
    Send := Pack($03, $01, lSendCont);
    PinCom.PutStrA(Send);
    Recv := UnPack($01, ret, CUF);

    if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then Result := gLR.Hint;
  finally
    PinCom.Free;
  end;
end;

function getLandiCardno(Track2, Track3: PChar): Boolean;
var
  lSendCont,Send,Recv: String;
  ret,i: Integer;
  CUF: Boolean;
  FOutStrA: array of string;
begin
  Result := false;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //卡信息
    lSendCont := 'A1';
    Send := Pack($03, $01, lSendCont);
    PinCom.PutStrA(Send);
    Recv := UnPack($01, ret, CUF);

    if ret = 0 then
    begin
      try
        SetLength(FOutStrA, getCharCount(Recv, Char($1C)) + 1);
        StrToArrayS(Recv, Char($1C), FOutStrA);

        if Length(FOutStrA) >= 6 then
        begin
          for i := 0 to High(FOutStrA) do
          begin
            case i of
              3: StrPcopy(Track2, StringReplace(StringReplace(DecryStrHex(FOutStrA[3], DecryStrHex(FOutStrA[5], IntimeMainKey)), 'F', '', [rfReplaceAll]), 'D', '=', [rfReplaceAll]));
              4: StrPcopy(Track3, StringReplace(StringReplace(DecryStrHex(FOutStrA[4], DecryStrHex(FOutStrA[5], IntimeMainKey)), 'F', '', [rfReplaceAll]), 'D', '=', [rfReplaceAll]));
            end;
            Result := true;
          end;
        end;
      except
      end;
    end;
  finally
    PinCom.Free;
  end;
end;

//浙江银联-UNIONPAYWALLET

function WalletConsume: Boolean;  //钱包消费
var
  lSendCont,Send,Recv,lID: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  req.Mode := '0';
  ret := -1;
  lID := FormatDateTime('hhmmss', now);

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //消费
    lSendCont := '41' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C) + Char($1C) + req.Amount + Char($1C) + gBankPrint;
    Send := Pack($03, cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret = 0 then
      begin
        Send := Pack($06, cuType, lSendCont, lID);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF, lID);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
        begin
          getLandiPrintmsgExt(Recv);
          Result := true;
        end;
      end
      else
        Recv := UnPack(cuType, ret, CUF, lID);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
    begin
      getLandiPrintmsgExt(Recv);
      req.Mode := '1';
      Result := true;
    end;
  finally
    if not Result then
    begin
      gLR.Mode := '1';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function WalletRepeal: Boolean;  //钱包撤消
var
  lSendCont,Send,Recv,lID: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  req.Mode := '0';
  ret := -1;
  lID := FormatDateTime('hhmmss', now);

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //消费撤消
    lSendCont := '42' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C) + Char($1C) + req.Amount + Char($1C) + gInvoice + Char($1C) + gBankPrint;
    Send := Pack($03, cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret = 0 then
      begin
        Send := Pack($06, cuType, lSendCont, lID);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF, lID);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
        begin
          getLandiPrintmsgExt(Recv);
          Result := true;
        end;
      end
      else
        Recv := UnPack(cuType, ret, CUF, lID);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
    begin
      getLandiPrintmsgExt(Recv);
      req.Mode := '1';
      Result := true;
    end;
  finally
    if not Result then
    begin
      gLR.Mode := '2';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function WalletRecall: Boolean;  //钱包退货
var
  lSendCont,Send,Recv,lID: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  req.Mode := '0';
  ret := -1;
  lID := FormatDateTime('hhmmss', now);
  //
  req.SaleType := 6; //隔日退货

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //退货
    lSendCont := '43' + Char($1C) + cuMerchantID + Char($1C) + cuTerminalID + Char($1C) + P_Company + Char($1C) + Char($1C) + req.Amount + Char($1C) + Char($1C) + Char($1C) + gBankPrint;
    Send := Pack($03, cuType, lSendCont, lID);
    PinCom.PutStrA(Send);
    Recv := UnPack(cuType, ret, CUF, lID);

    while CUF and (ret = 0) do
    begin
      lSendCont := ChinaUnion(Recv, ret);
      if ret = 0 then
      begin
        Send := Pack($06, cuType, lSendCont, lID);
        PinCom.PutStrA(Send);
        Recv := UnPack(cuType, ret, CUF, lID);
        if (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
        begin
          getLandiPrintmsgExt(Recv);
          Result := true;
        end;
      end
      else
        Recv := UnPack(cuType, ret, CUF, lID);
    end;

    //电话线模式
    if not Result and not CUF and (ret = 0) and (gLR.Instruction = Char($06)) and (gLR.Code = '00') then
    begin
      getLandiPrintmsgExt(Recv);
      req.Mode := '1';
      Result := true;
    end;
  finally
    if not Result then
    begin
      gLR.Mode := '6';
      SetBankTradeInfo(10);
    end;
    PinCom.Free;
  end;
end;

function doWallet(mode: ShortInt; flag: string): Boolean;
var
  lResult: Integer;
begin
  Result := false;
  res.Ok := 0;
  lResult := -1;

  case mode of
    1:
    begin
      if WalletConsume then lResult := 0;
    end;
    2:
    begin
      if flag = '8' then
      begin
        if WalletRecall then lResult := 0;
      end
      else
      begin
        if WalletRepeal then lResult := 0;
      end;
    end;
  end;

  if lResult = 0 then  //交易成功
  begin
    res.Ok := 1;
    Result := true;
  end
  else
  begin
    res.Ok := 0;
    StrToArray(res.Errmsg, gLR.Hint);
  end;
end;

function ProWalletCard(r: PayItem; tot, index : Integer): Boolean;
begin
  result := false;
  FillChar(res, Sizeof(res), Char(0));

  try
    req.SaleType := StrtoInt(r.Saletype);
    StrtoArray(req.Amount, dtos(r.Amount));
    StrtoArray(req.posno, Copy(P_BankSyjh, 6, 3));
    StrtoArray(req.track2, r.Track2);
    StrtoArray(req.track3, r.Track3);
    StrLCopy(gInvoice,r.Track1,32);
    if (StrLen(r.Cardid) <> 15) and (StrLen(r.Cardid) <> 18) then
    begin
      FillChar(req.Cardid, 15, ' ');
      req.Cardid[15] := Char(0);
    end
    else
    begin
      StrLCopy(req.Cardid, r.Cardid, Length(r.Cardid));
      req.Cardid[StrLen(r.Cardid)] := Char(0);
    end;
    FMsg('', '请刷卡(银行卡)', 0, false);
    MsgForm.Refresh;
    doWallet(req.SaleType, r.Mode);
    if res.Ok = 0 then
    begin
      MsgForm.Close;
      ShowMessageBox(res.Errmsg, '银联信息提示', MB_ICONINFORMATION + MB_OK);
    end
    else
    begin
      MsgForm.Close;
      try
        StrCopy(PayA[Index].PayID, res.Cardno);
      except
        on E: Exception do Debug('信用卡卡号赋值失败[' + IntToStr(Index) + ']:' + E.Message + IntToStr(E.HelpContext));
      end;
      result := true;
      try
        StrToArray(req.Mode, IntToStr(index + 1));
        //记载信用卡信息
        SetBankTradeInfo;
        //打印信用卡签购单
        if Pub_BankPaper <> '1' then
          PrintBankPaper(req, res, 1, 'N');
        //打印银行卡促销活动兑奖联
        if P_BankCoupon = 'Y' then
          PrintBankCoupon2(res);
      except
        Debug('信用卡签购单打印失败');
      end;
    end;
  except
    on E: Exception do Debug('信用卡卡交易主过程异常[' + E.Message + ']');
  end;
end;

//银联-通用

function LoadPosInf: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'PosInf.dll'
  else
    BankDLL := P_BankDLL;
  PosInfHandle := LoadLibrary(PChar(BankDLL)); //动态载入DLL，并返回其句柄
  if PosInfHandle <> 0 then //如果载入成功则获取函数地址
  begin
    @EmvBank := GetProcAddress(PosInfHandle, 'bankall');
    if (@EmvBank = nil) then
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreePosInf;
begin
  FreeLibrary(PosInfHandle); //调用完毕收回DLL占用的资源
end;

//武汉工行（北京捷文）

function LoadKeeperClientICBC: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'KeeperClient.dll'
  else
    BankDLL := P_BankDLL;
  KeeperClientHandle := LoadLibrary(PChar(BankDLL));
  if KeeperClientHandle <> 0 then
  begin
    @misposTrans := GetProcAddress(KeeperClientHandle, 'misposTrans');
    if (@misposTrans = nil) then
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeKeeperClientICBC;
begin
  FreeLibrary(KeeperClientHandle); //调用完毕收回DLL占用的资源
end;

//芜湖建行（北京捷文）

function LoadKeeperClientCCB: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'KeeperClient.dll'
  else
    BankDLL := P_BankDLL;
  KeeperClientHandle := LoadLibrary(PChar(BankDLL));
  if KeeperClientHandle <> 0 then
  begin
    @MisPosInterface := GetProcAddress(KeeperClientHandle, 'MisPosInterface');
    if (@MisPosInterface = nil) then
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeKeeperClientCCB;
begin
  FreeLibrary(KeeperClientHandle); //调用完毕收回DLL占用的资源
end;

//温岭农行、临海农行、成都建行（南京银石）

function LoadSoftposDll: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'SoftPos.dll'
  else
    BankDLL := P_BankDLL;
  SoftPosHandle := LoadLibrary(PChar(BankDLL));
  if SoftPosHandle <> 0 then
  begin
    @CreditTrans := GetProcAddress(SoftPosHandle, 'CreditTrans');
    if (@CreditTrans = nil) then
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeSoftposDll;
begin
  FreeLibrary(SoftPosHandle); //调用完毕收回DLL占用的资源
end;

//杭州银行

function LoadHZBankDll: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'hzmispos.dll'
  else
    BankDLL := P_BankDLL;
  HZBankHandle := LoadLibrary(PChar(BankDLL)); //动态载入DLL，并返回其句柄
  if HZBankHandle <> 0 then //如果载入成功则获取函数地址
  begin
    @HZBank := GetProcAddress(HZBankHandle, 'CreditTransUMS');
    if (@HZBank = nil) then
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeHZBankDll;
begin
  FreeLibrary(HZBankHandle); //调用完毕收回DLL占用的资源
end;

//工商银行

function LoadICBCDll: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'MposCore.dll'
  else
    BankDLL := P_BankDLL;
  ICBCHandle := LoadLibrary(PChar(BankDLL)); //动态载入DLL，并返回其句柄
  if ICBCHandle <> 0 then //如果载入成功则获取函数地址
  begin
    @MisTranSTD := GetProcAddress(ICBCHandle, 'DoICBCZJMisTranSTD');
    if (@MisTranSTD = nil) then
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeICBCDll;
begin
  FreeLibrary(ICBCHandle); //调用完毕收回DLL占用的资源
end;

//新利集团（唐山建行）
function LoadSingLeeDll: Boolean;
var
  BankDll: string;
begin
  Result := False;
  if P_BankDLL = '' then
    BankDll := 'sldll.dll'
  else
    BankDll := P_BankDLL;
  SingLeeHandle := LoadLibrary(PChar(BankDll));
  if SingLeeHandle <> 0 then
  begin
    @SingLeeMisTrans := GetProcAddress(SingLeeHandle, 'CardTrans');
    if @SingLeeMisTrans <> nil then
      Result := True
    else
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeSingLeeDll;
begin
  FreeLibrary(SingLeeHandle);
end;

//福建创识（绍兴农行）
function LoadEChaseDll: Boolean;
var
  BankDll: string;
begin
  Result := False;
  if P_BankDLL = '' then
    BankDll := 'sPosdll.dll'
  else
    BankDll := P_BankDLL;
  ChaseHandle := LoadLibrary(PChar(BankDll));
  if ChaseHandle <> 0 then
  begin
    @ChaseCardPay := GetProcAddress(ChaseHandle, 'CARDPAY');
    if @ChaseCardPay <> nil then
      Result := True
    else
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeEchaseDll;
begin
  FreeLibrary(ChaseHandle);
end;

//南京瑞康（柳州工行）
function LoadRiComDll: Boolean;
var
  BankDll: string;
begin
  Result := False;
  if P_BankDLL = '' then
    BankDll := 'trans.dll'
  else
    BankDll := P_BankDLL;
  RiComHandle := LoadLibrary(PChar(BankDll));
  if RiComHandle <> 0 then
  begin
    @RiComMenuApp := GetProcAddress(RiComHandle, 'MenuApp');
    if @RiComMenuApp <> nil then
      Result := True
    else
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeRiComDll;
begin
  FreeLibrary(RiComHandle);
end;

//上海杉德（北仑农行）
function LoadESandDll: Boolean;
var
  BankDll: string;
begin
  Result := False;
  if P_BankDLL = '' then
    BankDll := 'LibSand.dll'
  else
    BankDll := P_BankDLL;
  ESandHandle := LoadLibrary(PChar(BankDll));
  if ESandHandle <> 0 then
  begin
    @ESandTrans := GetProcAddress(ESandHandle, 'card_trans');
    if @ESandTrans <> nil then
      Result := True
    else
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeESandDll;
begin
  FreeLibrary(ESandHandle);
end;

//银联商务（苍南）
function LoadUmsUnionDll: Boolean;
var
  BankDll: string;
begin
  Result := False;
  if P_BankDLL = '' then
    BankDll := 'umsDevTool_sp30.dll'
  else
    BankDll := P_BankDLL;
  UmsHandle := LoadLibrary(PChar(BankDll));
  if UmsHandle <> 0 then
  begin
    @UmsProTrans := GetProcAddress(UmsHandle, 'YLSW_PROTRANS');
    if @UmsProTrans <> nil then
      Result := True
    else
      ShowMessageBox('初始化银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
  end
  else
    ShowMessageBox('载入银联函数库失败,信用卡交易不能正常执行', '系统警告', MB_ICONWARNING);
end;

procedure FreeUmsUnionDll;
begin
  FreeLibrary(UmsHandle);
end;

//MAINFUNC

function doNormal(mode: ShortInt; flag: String): Boolean;

  function doNormalLandi(mode: ShortInt; flag: string): Boolean;
  var
    lResult: Integer;
  begin
    Result := false;
    res.Ok := 0;
    lResult := -1;

    case mode of
      1:
      begin
        if flag = '9' then
        begin
          if LandiPartial then lResult := 0;
        end
        else
        begin
          if LandiConsume then lResult := 0;
        end;
      end;
      2:
      begin
        if flag = '8' then
        begin
          if LandiRecall then lResult := 0;
        end
        else
        begin
          if LandiRepeal then lResult := 0;
        end;
      end;
      3:
      if LandiInquiry then lResult := 0;
      4:
      begin
        if Pub_BankPaper <> '1' then
        begin
          if getLandiPrintmsg(True, False) then
            lResult := 0;
        end
        else
        begin
          if getLandiPrintmsg(True, True) then
            lResult := 0;
        end;
      end;
      5:
      if LandiSettle then lResult := 0;
    end;

    if lResult = 0 then  //交易成功
    begin
      res.Ok := 1;
      if (Trim(cuBankSrv) <> '') and (Trim(cuBankSrvPort) <> '') and (mode <> 5) and (mode <> 3) then
        getLandiPrintmsg(False, False);
      Result := true;
    end
    else
    begin
      res.Ok := 0;
      StrToArray(res.Errmsg, gLR.Hint);
    end;
  end;

  function doNormalHZBank(mode: ShortInt; flag: string): Boolean;
  var
    lResult,ires: Integer;
    InOutStr: array[0..1847] of char;
    FOutStrA: array of string;
  begin
    Result := false;
    res.Ok := 0;

    ZeroMemory(@InOutStr,Sizeof(InOutStr));
    FillChar(gHZBankIn, Sizeof(gHZBankIn), ' ');
    FillChar(gHZBankOut, Sizeof(gHZBankOut), Char(0));
    if LoadHZBankDll then
    begin
      lResult := -1;

      Str2Array(gHZBankIn.pos_trace, P_Syjh + '0' + FormatDateTime('YYYYMMDD', now) + P_seqno);
      if Trim(req.Amount) = '' then
        StrToArray(gHZBankIn.amount, '            ')
      else
        StrToArray(gHZBankIn.amount, req.Amount);

      case mode of
        1: gHZBankIn.trans := 'C';
        2:
        begin
          if flag = '8' then
          begin
            gHZBankIn.trans := 'R';
            Str2Array(gHZBankIn.old_reference, Copy(gInvoice, 1, 12));
            Str2Array(gHZBankIn.old_date, Copy(gInvoice, 13, 4));
          end
          else
          begin
            gHZBankIn.trans := 'D';
            Str2Array(gHZBankIn.old_trace, gInvoice);
          end;
        end;
        3: gHZBankIn.trans := 'I';
        4: gHZBankIn.trans := 'P';
        5: gHZBankIn.trans := 'O';
      end;
      Str2Array(InOutStr, gHZBankIn.pos_trace + gHZBankIn.posid + gHZBankIn.operid + gHZBankIn.trans + gHZBankIn.old_trace + gHZBankIn.old_reference + gHZBankIn.old_date + gHZBankIn.amount + gHZBankIn.card_no1 + gHZBankIn.card_no2 + gHZBankIn.memo);
      ires := HZBank(PChar(@InOutStr));
      if ires = 0 then
      begin
        StrToArray(gHZBankOut.pos_trace, Copy(InOutStr, 1, 16));
        StrToArray(gHZBankOut.resp_code, Copy(InOutStr, 17, 2));
        StrToArray(gHZBankOut.resp_name, Copy(InOutStr, 19, 30));
        StrToArray(gHZBankOut.print_msg, Copy(InOutStr, 49, 1800));
        if gHZBankOut.resp_code = '00' then lResult := 0;
      end;

      if lResult = 0 then  //交易成功
      begin
        res.Ok := 1;
        if mode <> 3 then      //查余额不打印信息
        begin
          FOutStrA := nil;
          SetLength(FOutStrA, getCharCount(gHZBankOut.print_msg, Char($1C)) + 1);
          StrToArrayS(gHZBankOut.print_msg, Char($1C), FOutStrA);
          if gHZBankIn.trans = 'O' then
          begin
            gBankSettle.MchtName := FOutStrA[2];  //商户名称
            gBankSettle.MchtCode := FOutStrA[0];  //商户代码
            gBankSettle.TermId := FOutStrA[1];  //终端号
            gBankSettle.Batchno := FOutStrA[4];  //批次号
            gBankSettle.DateTime := FOutStrA[5];  //日期时间
            gBankSettle.Inbs1 := FOutStrA[7];  //消费笔数
            gBankSettle.Inje1 := FOutStrA[8];  //消费金额
            gBankSettle.Inbs2 := FOutStrA[9];  //退货笔数
            gBankSettle.Inje2 := FOutStrA[10];  //退货金额
          end
          else
          begin
            cuMerchantID := FOutStrA[0];         //商户号
            cuTerminalID := FOutStrA[1];         //终端号
            StrToArray(res.Date, Copy(FOutStrA[13], 1, 4)); //交易日期
            StrToArray(res.Time, Copy(FOutStrA[13], 5, 6)); //交易时间
            StrToArray(res.Invoice, FOutStrA[12]);  //流水号
            StrToArray(res.Batchno, FOutStrA[11]);  //批次号
            StrToArray(res.Authno, FOutStrA[14]);  //授权码
            StrToArray(res.Cardno, FOutStrA[7]); //卡号
            StrToArray(res.Amount, FOutStrA[16]);  //金额
            StrToArray(res.RspCode, gHZBankOut.resp_code);  //置成功返回码
            StrToArray(res.LandiType, FOutStrA[9]);  //交易类型标志
            StrtoArray(gCard, ''); //银行号
            StrtoArray(gExpdate, FOutStrA[10]);  //失效日期
            StrToArray(gRefno, FOutStrA[15]);  //参考号
            if Length(FOutStrA) > 32 then
              StrToArray(gBankMemo, FOutStrA[32]);  //备注
          end;
        end;
        Result := true;
      end
      else
      begin
        res.Ok := 0;
        StrToArray(res.Errmsg, gHZBankOut.resp_name);
      end;
    end;
    FreeHZBankDll;
  end;

  function doNormalICBC(mode: ShortInt; flag: string): Boolean;
  var
    lResult: Integer;
    id: array[0..4] of Char;
    preinput: array[0..99] of char;
    rsv: array[0..0] of Char;
    outChar: PWideChar;
    sTemp: string;
    label labelEnd;
  begin
    Result := false;
    res.Ok := 0;

    FillChar(id, Sizeof(id), Char(0));
    FillChar(preinput, Sizeof(preinput), Char(0));
    FillChar(gICBCOut, Sizeof(gICBCOut), Char(0));
    if LoadICBCDll then
    begin
      lResult := -1;

      case mode of
        1:
        begin
          id := '1001';
          Str2Array(preinput, 'AMT1=' + req.Amount);
        end;
        2:
        begin
          if flag = '8' then
          begin
            id := '1102';
            Str2Array(preinput, 'AMT1=' + req.Amount + ',I1=' + Copy(gInvoice, 1, 8) + ',I2=' + Copy(gInvoice, 9, 8) + ',I3=' + Copy(gInvoice, 17, Length(gInvoice) - 16));
          end
          else
          begin
            id := '1101';
            Str2Array(preinput, 'AMT1=' + req.Amount + ',I1=' + Copy(gInvoice, 1, 8));
          end;
        end;
        3: id := '2002';
        4: id := '4005';                        //重打印4005、文档未写
        5: goto labelEnd;
      end;
      outChar := MisTranSTD(PWideChar(@id), PWideChar(@preinput), PWideChar(@rsv), PWideChar(@rsv), PWideChar(@rsv));
      sTemp := outChar;
      StrCopy(PChar(@gICBCOut), PChar(sTemp));
      if gICBCOut.RspCode = '00' then lResult := 0;

      if lResult = 0 then  //交易成功
      begin
        res.Ok := 1;
        StrToArray(res.Date, Copy(gICBCOut.ChargeDate, 5, 4)); //交易日期
        StrToArray(res.Time, gICBCOut.ChargeTime); //交易时间
        StrToArray(res.Invoice, gICBCOut.Trace);  //流水号
        StrToArray(res.Batchno, gICBCOut.BatchNo);  //批次号
        StrToArray(res.Authno, gICBCOut.AuthId); //授权码
        StrToArray(res.Cardno, gICBCOut.Cardno); //卡号
        StrToArray(res.Amount, gICBCOut.Amount);  //金额
        StrToArray(res.BankCode, gICBCOut.BankCode); //银行号
        StrToArray(res.RspCode, gICBCOut.RspCode);  //置成功返回码
        cuTerminalID := PChar(Copy(gICBCOut.TermId, Length(gICBCOut.TermId) - 9, 8));    //终端号
        cuMerchantID := PChar(Copy(gICBCOut.Memo, Pos(':', gICBCOut.Memo) + 1, 15));     //商户号

        //交易类型
        if id = '1001' then
          res.LandiType := '01'
        else if id = '1101' then
          res.LandiType := '02'
        else if id = '1102' then
          res.LandiType := '03';
        StrtoArray(gCard, gICBCOut.BankCode); //银行号
        StrtoArray(gExpdate, gICBCOut.Expr); //失效日期
        StrToArray(gRefno, gICBCOut.RefNo); //参考号
        StrToArray(gBankMemo, '终端编号: ' + PChar(Copy(gICBCOut.TermId, 1, Length(gICBCOut.TermId))));  //备注字段存终端号
        if mode = 4 then
          PrintBankPaper(req, res, 1, 'Y');
        Result := true;
      end
      else
      begin
        res.Ok := 0;
        StrCopy(res.Errmsg, PChar(Copy(sTemp, 3, Length(sTemp) - 2)));
      end;
      labelEnd:
    end;
    FreeICBCDll;
  end;

  function doNormalKeeperClientICBC(mode: ShortInt): Boolean;
  var
    lResult,i: Integer;
  begin
    Result := false;
    res.Ok := 0;

    FillChar(sticbcmis_req, Sizeof(sticbcmis_req), ' ');
    FillChar(sticbcmis_res, Sizeof(sticbcmis_res), ' ');

    if LoadKeeperClientICBC then
    begin
      lResult := -1;

      Str2Array(sticbcmis_req.TransAmount, req.Amount);
      Str2Array(sticbcmis_req.platId, P_Syjh);
      Str2Array(sticbcmis_req.operId, P_Gh);

      case mode of
        1:
        begin
          sticbcmis_req.TransType := '05';
        end;
        2:
        begin
          sticbcmis_req.TransType := '04';
          Str2Array(sticbcmis_req.ReferNo, Copy(gInvoice, 1, 8));
          Str2Array(sticbcmis_req.TransDate, Copy(gInvoice, 9, 8));
          Str2Array(sticbcmis_req.TerminalId, Copy(gInvoice, 17, 15));
        end;
        3:
        begin
          sticbcmis_req.TransType := '10';
        end;
        4:
        begin
          sticbcmis_req.TransType := '13';
          Str2Array(sticbcmis_req.ReferNo, '00000000');
        end;
        5:
        begin
          sticbcmis_req.TransType := '15';
        end;
      end;

      if misposTrans(Pchar(@sticbcmis_req), Pchar(@sticbcmis_res)) = 0 then
      begin
        if sticbcmis_res.RspCode = '00' then lResult := 0;
      end;

      if lResult = 0 then  //交易成功
      begin
        res.Ok := 1;
        StrtoArray(res.Date, Copy(sticbcmis_res.TransDate, 5, 4)); //交易日期
        StrtoArray(res.Time, Copy(sticbcmis_res.TransTime, 1, 6)); //交易时间
        StrtoArray(res.Invoice, sticbcmis_res.TerminalTraceNo); //中心流水
        StrtoArray(res.Batchno, sticbcmis_res.TerminalBatchNo); //批次号
        StrtoArray(res.Authno, sticbcmis_res.AuthNo); //授权号
        StrtoArray(res.Cardno, sticbcmis_res.CardNo); //卡号
        StrtoArray(res.Amount, sticbcmis_res.Amount); //金额
        StrtoArray(res.RspCode, sticbcmis_res.RspCode); //应答码
        StrtoArray(res.LandiType, sticbcmis_res.TransType); //设备交易类型

        StrtoArray(gCard, ''); //银行号
        StrtoArray(gRefno, sticbcmis_res.ReferNo); //系统跟踪号
        StrtoArray(gExpdate, sticbcmis_res.ExpDate); //失效日期
        if mode = 4 then
          PrintBankPaper(req, res, 1, 'Y')
        else if mode = 5 then
        begin
          if FileExists(g_path + P_BankPaper) then
          begin
            if P_BankPaperPrint <> 'N' then
            begin
              for i := 1 to StrtoInt(P_BankPaperCount) do
                DoPrint(g_path + P_BankPaper, 1, false);
            end;
          end
        end;

        Result := true;
      end
      else
      begin
        res.Ok := 0;
        StrToArray(res.Errmsg, sticbcmis_res.RspMessage);
      end;
    end;
    FreeKeeperClientICBC;
  end;

  function doNormalKeeperClientCCB(mode: ShortInt; flag: String): Boolean;
  var
    lResult: Integer;
  begin
    Result := false;
    res.Ok := 0;

    FillChar(stccbmis_req, Sizeof(stccbmis_req), ' ');
    FillChar(stccbmis_res, Sizeof(stccbmis_res), ' ');

    if LoadKeeperClientCCB then
    begin
      lResult := -1;

      Str2Array(stccbmis_req.TransAmount, req.Amount);

      Str2Array(stccbmis_req.cashPcNum, P_Syjh);
      Str2Array(stccbmis_req.cashierNum, P_Gh);

      case mode of
        1:
        begin
          stccbmis_req.TransType := 'S1';
          Str2Array(stccbmis_req.MisTrace, P_Seqno);
        end;
        2:
        begin
          if flag = '8' then
          begin
            stccbmis_req.TransType := 'S3';
            Str2Array(stccbmis_req.MisTrace, P_Seqno);
            Str2Array(stccbmis_req.oldHostTrace, Copy(gInvoice, 1, 12));
            Str2Array(stccbmis_req.oldTransDate, Copy(gInvoice, 13, 8));
          end
          else
          begin
            stccbmis_req.TransType := 'S2';
            Str2Array(stccbmis_req.MisTrace, P_Seqno);
            Str2Array(stccbmis_req.oldPostrace, gInvoice);
          end;
        end;
        3:
        begin
          stccbmis_req.TransType := 'S4';
        end;
        4:
        begin
          stccbmis_req.TransType := 'Q3';
          Str2Array(stccbmis_req.oldPostrace, '');
        end;
        5:
        begin
          stccbmis_req.TransType := 'Q2';
        end;
      end;

      if MisPosInterface(Pchar(@stccbmis_req), Pchar(@stccbmis_res)) = 0 then
      begin
        if stccbmis_res.RspCode = '00' then lResult := 0;
      end;

      if lResult = 0 then  //交易成功
      begin
        res.Ok := 1;
        StrtoArray(res.Date, Copy(stccbmis_res.TransDate, 5, 4)); //交易日期
        StrtoArray(res.Time, stccbmis_res.TransTime); //交易时间
        StrtoArray(res.Invoice, stccbmis_res.posTraceNum); //中心流水
        StrtoArray(res.Batchno, stccbmis_res.batchNum); //批次号
        StrtoArray(res.Authno, stccbmis_res.authorNum); //授权号
        StrtoArray(res.Cardno, stccbmis_res.transCardNum); //卡号
        StrtoArray(res.Amount, stccbmis_res.transAmount); //金额
        StrtoArray(res.RspCode, stccbmis_res.rspCode); //应答码
        StrtoArray(res.LandiType, stccbmis_res.transType); //设备交易类型

        StrtoArray(gCard, ''); //银行号
        StrtoArray(gRefno, stccbmis_res.hostTrace); //系统跟踪号
        StrtoArray(gExpdate, stccbmis_res.expDate); //失效日期
        if mode = 4 then
          PrintBankPaper(req, res, 1, 'Y');
        Result := true;
      end
      else
      begin
        res.Ok := 0;
        StrToArray(res.Errmsg, stccbmis_res.rspMsg);
      end;
    end;
    FreeKeeperClientCCB;
  end;

  function doNormalEmv(mode: ShortInt; flag: String): Boolean;
  var
    lResult,ires: Integer;
  begin
    Result := false;
    res.Ok := 0;

    FillChar(gEmvRequest, Sizeof(gEmvRequest), ' ');
    FillChar(gEmvResponse, Sizeof(gEmvResponse), ' ');
    if LoadPosInf then
    begin
      lResult := -1;
      Str2Array(gEmvRequest.posid, P_Syjh);
      Str2Array(gEmvRequest.operid, P_Gh);
      Str2Array(gEmvRequest.amount, req.Amount);
      Randomize;
      Str2Array(gEmvRequest.lrc, IntToStr(Random(899) + 1));

      case mode of
        1: gEmvRequest.trans := '00';
        2:
        begin
          if flag = '8' then
          begin
            gEmvRequest.trans := '02';
            Str2Array(gEmvRequest.old_reference, Copy(gInvoice, 1, 12));
            Str2Array(gEmvRequest.old_date, Copy(gInvoice, 13, 8));
          end
          else
          begin
            gEmvRequest.trans := '01';
            Str2Array(gEmvRequest.old_trace, gInvoice);
          end;
        end;
        3: gEmvRequest.trans := '03';
        4: gEmvRequest.trans := '04';
        5: gEmvRequest.trans := '06';
      end;

      ires := EmvBank(Pchar(@gEmvRequest), Pchar(@gEmvResponse));
      if ires = 0 then
      begin
        if gEmvResponse.resp_code = '00' then lResult := 0;
      end;

      if lResult = 0 then  //交易成功
      begin
        res.Ok := 1;
        StrToArray(res.LandiType, gEmvRequest.trans);
        Inc(res.LandiType[1]);                          //交易类型
        StrtoArray(res.Date, gEmvResponse.ChargeDate);  //日期
        StrtoArray(res.Time, gEmvResponse.ChargeTime);  //时间
        StrtoArray(res.Invoice, gEmvResponse.trace);  //流水号
        StrtoArray(res.Batchno, gEmvResponse.BatchNo);  //批次号
        StrtoArray(res.Authno, gEmvResponse.AuthId);  //授权码
        StrtoArray(res.Cardno, gEmvResponse.card_no); //卡号
        StrtoArray(res.Amount, gEmvResponse.amount);  //金额
        StrtoArray(res.BankCode, gEmvResponse.bank_code);  //银行号
        StrToArray(res.RspCode, gEmvResponse.resp_code);  //置成功返回码

        getTransStr(PChar(g_path + 'Banks.ini'), res.BankCode, gCard); //发卡行
        StrtoArray(gRefno, gEmvResponse.RefNo); //系统跟踪号
        StrtoArray(gExpdate, gEmvResponse.expr); //失效日期
        Result := true;
      end
      else
      begin
        res.Ok := 0;
        fillchar(gRescode, length(gRescode),char(0));
        Move(gEmvResponse.resp_code, gRescode, 2);
        if getTransStr(PChar(g_path + 'Rsp.ini'), gRescode, res.Errmsg) <> 0 then
          StrCopy(res.Errmsg, '银联或银行未知错误!');
      end;
    end;
    FreePosInf;
  end;

  function doNormalYS(mode: ShortInt; flag: string): Boolean;
  var
    lResult,ires: Integer;
  begin
    Result := false;
    res.Ok := 0;

    FillChar(gStrIn, Sizeof(gStrIn), ' ');
    FillChar(gStrOut, Sizeof(gStrOut), Char(0));
    if LoadSoftposDll then
    begin
      lResult := -1;

      Str2Array(gStrIn.pos_no, P_Syjh);
      Str2Array(gStrIn.teller_no, P_Gh);
      if Trim(req.Amount) = '' then
        StrToArray(gStrIn.tr_amt, '000000000000')
      else
        StrToArray(gStrIn.tr_amt, req.Amount);

      case mode of
        1: gStrIn.txn_no := 'C';
        2:
        begin
          if flag = '8' then
            gStrIn.txn_no := 'R'
          else
            gStrIn.txn_no := 'D';
        end;
        3: gStrIn.txn_no := 'I';
        4: gStrIn.txn_no := '0';
        5: gStrIn.txn_no := '0';
      end;
      ires := CreditTrans(Pchar(@gStrIn), Pchar(@gStrOut));
      if ires = 0 then
      begin
        if gStrOut.rc = '00' then lResult := 0;
      end;

      if lResult = 0 then  //交易成功
      begin
        res.Ok := 1;
        StrToArray(res.Date, gStrOut.txn_date); //交易日期
        StrToArray(res.Time, gStrOut.txn_time); //交易时间
        StrToArray(res.Invoice, gStrOut.pos_systrace);  //流水号
        StrToArray(res.Cardno, gStrOut.pan); //卡号
        StrToArray(res.Amount, gStrOut.tr_amt);  //金额
        StrToArray(res.RspCode, gStrOut.rc);  //置成功返回码
        if gStrOut.txn_no = 'C' then  //交易类型标志
          StrToArray(res.LandiType, '01')
        else if gStrOut.txn_no = 'D' then
          StrToArray(res.LandiType, '02')
        else if gStrOut.txn_no = 'R' then
          StrToArray(res.LandiType, '03')
        else
          StrToArray(res.LandiType, '00');

        StrtoArray(gCard, ''); //银行号
        StrToArray(gRefno, gStrOut.RRN);  //参考号
        if mode = 4 then
          PrintBankPaper(req, res, 1, 'Y');
        Result := true;
      end
      else
      begin
        res.Ok := 0;
        fillchar(gRescode, length(gRescode), char(0));
        Move(gStrOut.rc, gRescode, 2);
        if getTransStr(PChar(g_path + 'RSP.ini'), gRescode, res.Errmsg) <> 0 then
          StrCopy(res.Errmsg, '银联或银行未知错误!');
      end;
    end;
    FreeSoftposDll;
  end;

  function doNormalSingLee(mode: ShortInt; flag: string): Boolean;
  var
    lResult,ires: Integer;
  begin
    Result := False;
    res.Ok := 0;

    FillChar(gXLCCBIn, SizeOf(gXLCCBIn), ' ');
    FillChar(gXLCCBOut, SizeOf(gXLCCBOut), ' ');
    if LoadSingLeeDll then
    begin
      lResult := -1;

      if Trim(req.Amount) = '' then
        StrToArray(gXLCCBIn.transAmount, '000000000000')
      else
        StrToArray(gXLCCBIn.transAmount, req.Amount);
      gXLCCBIn.cardType := 'H';
      Randomize;
      Str2Array(gXLCCBIn.transIndex, FormatDateTime('YYYYMMDD', Now) + P_Seqno + IntToStr(Random(99)));
      case mode of
        1: gXLCCBIn.transType := '01';
        2:
          begin
            if flag = '8' then
            begin
              gXLCCBIn.transType := '09';
              Str2Array(gXLCCBIn.referenceNo, Copy(gInvoice, 1, 12));
              Str2Array(gXLCCBIn.old_operdate, Copy(gInvoice, 13, 8));
            end
            else begin
              gXLCCBIn.transType := '02';
              Str2Array(gXLCCBIn.pos_trace, Copy(gInvoice, 1, 6));
            end;
          end;
        3: gXLCCBIn.transType := '03';
        4: gXLCCBIn.transType := '12';
        5: gXLCCBIn.transType := '14';
      end;
      ires := SingLeeMisTrans(PChar(@gXLCCBIn), PChar(@gXLCCBOut));
      if ires = 0 then
      begin
        if gXLCCBOut.respCode = '000000' then lResult := 0;
      end;

      if lResult = 0 then
      begin
        res.Ok := 1;
        res.RspCode := '00';                                          //应答码
        StrToArray(res.LandiType, gXLCCBOut.transCode);               //交易类型
        StrToArray(res.Date, Copy(gXLCCBOut.bankSrvDate, 5, 4));      //交易日期
        StrToArray(res.Time, gXLCCBOut.bankSrvTime);                  //交易时间
        StrToArray(res.Amount, gXLCCBOut.transAmount);                //交易金额
        StrToArray(res.Invoice, gXLCCBOut.pos_trace);                 //商户流水号
        StrToArray(res.Batchno, gXLCCBOut.batchNo);                   //批次号
        StrToArray(res.Authno, gXLCCBOut.authorNo);                   //授权号
        StrToArray(res.BankCode, gXLCCBOut.bankCode);                 //银行号
        StrToArray(res.Cardno, gXLCCBOut.cardNo);                     //卡号

        StrToArray(gCard, gXLCCBOut.cardNo);                          //卡号
        StrToArray(gExpdate, gXLCCBOut.expDate);                      //有效期
        StrToArray(gRefno, gXLCCBOut.refNo);                          //参考号
        if mode = 4 then
          PrintBankPaper(req, res, 1, 'Y');
        Result := True;
      end
      else begin
        res.Ok := 0;
        StrToArray(res.Errmsg, gXLCCBOut.respDesc);
      end;
    end;
    FreeSingLeeDll;
  end;

  function doNormalEChase(mode: ShortInt; flag: string): Boolean;
  var
    lResult,ires: Integer;
    stR: TStringList;
    dTemp: Double;
  begin
    Result := False;
    res.Ok := 0;

    FillChar(gChaseIn, SizeOf(gChaseIn), ' ');
    FillChar(gChaseOut, SizeOf(gChaseOut), ' ');
    if LoadEChaseDll then
    begin
      lResult := -1;

      if Trim(req.Amount) = '' then
        StrToArray(gChaseIn.amount, '000000000000')
      else
        StrToArray(gChaseIn.amount, req.Amount);
      Str2Array(gChaseIn.syjh, P_Syjh);
      Str2Array(gChaseIn.gh, P_Gh);
      case mode of
        1: gChaseIn.transType := 'S01';
        2:
          begin
            if flag = '8' then
            begin
              gChaseIn.transType := 'R01';
              Str2Array(gChaseIn.infor, Copy(gInvoice, 1, 16));
            end
            else begin
              gChaseIn.transType := 'V01';
              Str2Array(gChaseIn.infor, Copy(gInvoice, 1, 6));
            end;
          end;
        3: gChaseIn.transType := 'B01';
        4: gChaseIn.transType := 'P01';
        5: gChaseIn.transType := 'ST1';
      end;
      ires := ChaseCardPay(PChar(@gChaseIn), PChar(@gChaseOut));
      if ires = 0 then
      begin
        if gChaseOut.respCode = '00' then lResult := 0;
      end;
      
      if lResult = 0 then
      begin          
        res.Ok := 1;
        StrToArray(res.RspCode, gChaseOut.respCode);                //返回码
        StrToArray(res.LandiType, gChaseOut.transType);             //交易类型
        StrToArray(res.Cardno, gChaseOut.cardNo);                   //卡号
        StrToArray(gCard, gChaseOut.cardNo);
        if UpperCase(Copy(gChaseOut.memo, 1, 3)) = 'VOU' then
        begin
          stR := SplitString(PChar(@gChaseOut.memo), '|');          //凭证信息域
          StrToArray(res.Date, Copy(stR.Strings[12], 1, 4));        //交易日期
          StrToArray(res.Time, Copy(stR.Strings[12], 5, 6));        //交易时间
          StrToArray(res.Invoice, stR.Strings[11]);                 //流水号
          StrToArray(res.Batchno, stR.Strings[10]);                 //批次号
          StrToArray(res.Authno, stR.Strings[13]);                  //授权号
          dTemp := (StrToFloatDef(stR.Strings[15], 0) + StrToFloatDef(stR.Strings[20], 0)) / 100;
          StrToArray(res.Amount, dtos(dTemp));                      //交易金额

          StrToArray(gBankMemo, stR.Strings[16]);                   //备注
          StrToArray(gExpdate, stR.Strings[9]);                     //有效期
          StrToArray(gRefno, stR.Strings[14]);                      //参考号
        end;
        Result := True;
      end
      else begin
        res.Ok := 0;
        fillchar(gRescode, length(gRescode), char(0));
        Move(gChaseOut.respCode, gRescode, 2);
        if getTransStr(PChar(g_path + 'RSP.ini'), gRescode, res.Errmsg) <> 0 then
          StrCopy(res.Errmsg, gChaseOut.respDesc);
      end;
    end;
    FreeEchaseDll;
  end;

  function doNormalRiCom(mode: ShortInt; flag: string): Boolean;
  var
    lResult,ires: Integer;
    label LabelReprint;
  begin
    Result := False;
    res.Ok := 0;

    FillChar(gRiComIn, SizeOf(gRiComIn), '0');
    FillChar(gRiComOut, SizeOf(gRiComOut), ' ');
    if LoadRiComDll then
    begin
      lResult := -1;

      if Trim(req.Amount) = '' then
        StrToArray(gRiComIn.amount, '000000000000')
      else
        StrToArray(gRiComIn.amount, req.Amount);
      Str2Array(gRiComIn.gh, P_Gh);
      Str2Array(gRiComIn.syjh, P_Syjh);
      Str2Array(gRiComIn.seqno, Days + P_Syjh + P_Seqno);
      case mode of
        1: gRiComIn.transType := '05';
        2:
          begin
            if flag = '8' then
            begin
              gRiComIn.transType := '08';
              Str2Array(gRiComIn.old_index, Copy(gInvoice, 1, 12));
              Str2Array(gRiComIn.old_operdate, Copy(gInvoice, 13, 8));
            end
            else begin
              gRiComIn.transType := '07';
              Str2Array(gRiComIn.old_trace, Copy(gInvoice, 1, 6));
            end;
          end;
        3: gRiComIn.transType := '06';
        4: goto LabelReprint;
        5: gRiComIn.transType := 'ff';
      end;
      //先删除toprint.txt
      if FileExists(g_path + P_BankPaper) then
        DeleteFile(PChar(g_path + P_BankPaper));
      ires := RiComMenuApp(PChar(@gRiComIn), PChar(@gRiComOut));
      if ires = 1 then
      begin
        if gRiComOut.respCode = '00' then lResult := 0;
      end;

      if lResult = 0 then
      begin
        labelReprint:
          begin
            res.Ok := 1;
            StrToArray(res.RspCode, gRiComOut.respCode);                //应答码
            StrToArray(res.Amount, gRiComOut.amount);                   //交易金额
            StrToArray(res.Cardno, gRiComOut.cardno);                   //卡号
            StrToArray(res.LandiType, gRiComIn.transType);              //交易类型
            StrToArray(res.Invoice, gRiComOut.batchNo);                 //凭证号
            StrToArray(res.Date, Copy(gRiComOut.operdate, 5, 4));       //交易日期
            StrToArray(res.Time, gRiComOut.opertime);                   //交易时间

            StrToArray(gCard, gRiComOut.cardbank);                      //发卡行
            StrToArray(gRefno, gRiComOut.index);                        //检索号

            if mode = 4 then
            begin
              StrToArray(res.Amount, gRiComIn.amount);                   //交易金额
              PrintBankPaper(req, res, 1, 'Y');
            end;
          end;
        Result := True;
      end
      else begin
        res.Ok := 0;
        fillchar(gRescode, length(gRescode), char(0));
        Move(gRiComOut.respCode, gRescode, 2);
        if getTransStr(PChar(g_path + 'RSP.ini'), gRescode, res.Errmsg) <> 0 then
          StrCopy(res.Errmsg, gRiComOut.respDesc);
      end;
    end;
    FreeRiComDll;
  end;

  function doNormalESand(mode: ShortInt; flag: string): Boolean;
  var
    lResult: Integer;
    label lblReprint;
  begin
    Result := False;
    res.Ok := 0;

    FillChar(gESandIn, SizeOf(gESandIn), ' ');
    FillChar(gESandOut, SizeOf(gESandOut), ' ');
    if LoadESandDll then
    begin
      lResult := -1;

      if Trim(req.Amount) = '' then
        StrToArray(gESandIn.Amount, '000000000000')
      else
        StrToArray(gESandIn.Amount, req.Amount);
      Str2Array(gESandIn.CashRegNo, '000' + P_Syjh);
      Str2Array(gESandIn.CasherNo, g_counter);
      gESandIn.OperateType := 'A0';
      gESandIn.CardType := '01';
      case mode of
        1: gESandIn.TransType := '30';
        2:
          begin
            if flag = '8' then
            begin
              gESandIn.TransType := '50';
              Str2Array(gESandIn.Reserved, Copy(gInvoice, 1, 16));
            end
            else begin
              gESandIn.TransType := '40';
              Str2Array(gESandIn.OriginTraceNo, Copy(gInvoice, 1, 6));
            end;
          end;
        3: gESandIn.TransType := '80';
        4: goto lblReprint;
        5: gESandIn.TransType := '92';
      end;
      ESandTrans(StrToInt(Copy(P_CreditPort, 4, 1)), PChar(@gESandIn), PChar(@gESandOut));
      if gESandOut.ResponseCode = '00' then lResult := 0;

      if lResult = 0 then
      begin
        res.Ok := 1;
        StrToArray(res.RspCode, gESandOut.ResponseCode);        //应答码
        StrToArray(res.LandiType, gESandOut.TransType);         //交易类型
        StrToArray(res.Amount, gESandOut.Amount);               //交易金额
        StrToArray(res.Cardno, gESandOut.CardNo);               //卡号
        StrToArray(res.BankCode, gESandOut.BankNo);             //银行号
        StrToArray(res.Date, Copy(gESandOut.TransDate, 5, 4));  //交易日期
        StrToArray(res.Time, gESandOut.TransTime);              //交易时间
        StrToArray(res.Authno, gESandOut.Auth_Code);            //授权号
        StrToArray(res.Batchno, gESandOut.SellteNum);           //批次号
        StrToArray(res.Invoice, gESandOut.CashTraceNo);         //交易流水号

        StrToArray(gExpdate, gESandOut.Exp_Date);               //有效日期
        StrToArray(gRefno, gESandOut.SysRefNo);                 //参考号
        StrToArray(gCard, gESandOut.BankNo);                    //银行代码
        Result := True;
      end
      else begin
        res.Ok := 0;
        StrToArray(res.Errmsg, gESandOut.ResponseMsg);
      end;
      lblReprint:
    end;
    FreeESandDll;
  end;

  function doNormalUmsUnion(mode: ShortInt; flag: string): Boolean;
  var
    lResult, ires: Integer;
    sTr: TStringList;
  begin
    Result := False;
    res.Ok := 0;

    FillChar(gUmsUnionIn, SizeOf(gUmsUnionIn), Char(0));
    if LoadUmsUnionDll then
    begin
      lResult := -1;

      if Trim(req.Amount) = '' then
        gUmsUnionIn._Amt := '0.00'
      else begin
        StrToArray(gUmsUnionIn._Amt, Copy(req.Amount, 1, 10) + '.' + Copy(req.Amount, 11, 2));
      end;
      gUmsUnionIn._Channel := '01';
      Str2Array(gUmsUnionIn._Mcht, '000000000000000');
      Str2Array(gUmsUnionIn._Oper, P_Gh);
      Str2Array(gUmsUnionIn._Serial, Days + P_Syjh + P_seqno);
      case mode of
        1: gUmsUnionIn._Type := '01';
        2:
          begin          
            gUmsUnionIn._Type := '02';
            if flag = '8' then
            begin
              Str2Array(gUmsUnionIn._Pserial, Copy(gInvoice, 1, 12));
              Str2Array(gUmsUnionIn._BatchNo, Copy(gInvoice, 13, 8));
            end
            else begin
              Str2Array(gUmsUnionIn._Pserial, Copy(gInvoice, 1, 6));
              Str2Array(gUmsUnionIn._BatchNo, Copy(gInvoice, 7, 6));
            end;
          end;
        3, 4, 5:  gUmsUnionIn._Type := '03';
      end;
      ires := UmsProTrans(PChar(@(gUmsUnionIn._Channel)), PChar(@(gUmsUnionIn._Type)),
          PChar(@(gUmsUnionIn._Amt)), PChar(@(gUmsUnionIn._Mcht)), PChar(@(gUmsUnionIn._Oper)),
          PChar(@(gUmsUnionIn._BatchNo)), PChar(@(gUmsUnionIn._Pserial)), PChar(@(gUmsUnionIn._CardInfo)),
          PChar(@(gUmsUnionIn._CardNum)), PChar(@(gUmsUnionIn._Serial)), PChar(@(gUmsUnionIn._RetInfo)));
      if ires = 0 then
      begin
        lResult := 0;
      end;

      if lResult = 0 then
      begin
        res.Ok := 1;
        if mode in [1, 2] then       //消费、撤销
        begin
          sTr := SplitString(PChar(@(gUmsUnionIn._RetInfo)), '|');
          StrToArray(res.Amount, sTr[2]);
          StrToArray(res.LandiType, sTr[1]);
          StrToArray(res.RspCode, '00');
          StrToArray(res.Invoice, sTr[4]);
          StrToArray(res.Batchno, sTr[3]);
          StrToArray(res.Cardno, sTr[9]);
          StrToArray(res.Date, Copy(sTr[11], 5, 4));
          StrToArray(res.Time, Copy(sTr[11], 9, 6));
          StrToArray(res.Authno, sTr[12]);
          StrToArray(res.BankCode, sTr[8]);

          StrToArray(gCard, sTr[8]);
          StrToArray(gRefno, sTr[10]);
          StrToArray(gBankMemo, sTr[17]);
        end;
        Result := True;
      end
      else begin
        res.Ok := 0;
        StrToArray(res.Errmsg, gUmsUnionIn._RetInfo);
      end;
    end;
    FreeUmsUnionDll;
  end;

begin
  if P_BankType = '3' then
    Result := doNormalUmsUnion(mode, flag)     //银联商务
  else if P_BankType = '7' then
    Result := doNormalESand(mode, flag)  //上海杉德（北仑农行）
  else if P_BankType = '10' then
    result := doNormalLandi(mode, flag) //银泰-通用（联迪、百富）
  else if P_BankType = '11' then
    result := doNormalHZBank(mode, flag)  //杭州银行
  else if P_BankType = '12' then
    result := doNormalICBC(mode, flag)  //工商银行
  else if P_BankType = '15' then
    result := doNormalRiCom(mode, flag)  //南京瑞康（柳州工行）
  else if P_BankType = '17' then
    result := doNormalKeeperClientCCB(mode, flag) //北京捷文（芜湖建行）
  else if P_BankType = '18' then
    result := doNormalKeeperClientICBC(mode) //北京捷文（武汉工行）
  else if P_BankType = '19' then
    Result := doNormalSingLee(mode, flag)  //新利集团（唐山建行）
  else if P_BankType = '20' then
    Result := doNormalEChase(mode, flag)  //福建创识（绍兴农行）
  else if P_BankType = '21' then
    result := doNormalEmv(mode, flag) //银联-通用（DLL）
  else if P_BankType = '22' then
    result := doNormalYS(mode, flag) //南京银石（温岭农行、临海农行、成都建行）
  else
    result := False;
end;

function ProCreditCard(r: PayItem; tot, index : Integer): Boolean;
begin
  result := false;
  FillChar(res, Sizeof(res), Char(0));

  try
    req.SaleType := StrtoInt(r.Saletype);
    StrtoArray(req.Amount, dtos(r.Amount));
    StrtoArray(req.posno, Copy(P_BankSyjh, 6, 3));
    StrtoArray(req.track2, r.Track2);
    StrtoArray(req.track3, r.Track3);
    StrLCopy(gInvoice,r.Track1,32);
    if (StrLen(r.Cardid) <> 15) and (StrLen(r.Cardid) <> 18) then
    begin
      FillChar(req.Cardid, 15, ' ');
      req.Cardid[15] := Char(0);
    end
    else
    begin
      StrLCopy(req.Cardid, r.Cardid, Length(r.Cardid));
      req.Cardid[StrLen(r.Cardid)] := Char(0);
    end;
    FMsg('', '请刷卡(银行卡)', 0, false);
    MsgForm.Refresh;
    doNormal(req.SaleType, r.Mode);
    if res.Ok = 0 then
    begin
      MsgForm.Close;
      ShowMessageBox(res.Errmsg, '银联信息提示', MB_ICONINFORMATION + MB_OK);
    end
    else
    begin
      MsgForm.Close;
      try
        StrCopy(PayA[Index].PayID, res.Cardno);
      except
        on E: Exception do Debug('信用卡卡号赋值失败[' + IntToStr(Index) + ']:' + E.Message + IntToStr(E.HelpContext));
      end;
      result := true;
      try
        StrToArray(req.Mode, IntToStr(index + 1));
        //记载信用卡信息
        SetBankTradeInfo;
        //打印信用卡签购单
        if Pub_BankPaper <> '1' then
          PrintBankPaper(req, res, 1, 'N');
        //打印银行卡促销活动兑奖联
        if P_BankCoupon = 'Y' then
          PrintBankCoupon2(res);
      except
        Debug('信用卡签购单打印失败');
      end;
    end;
  except
    on E: Exception do Debug('信用卡卡交易主过程异常[' + E.Message + ']');
  end;
end;

function OnBankSettle: Boolean;
begin
  Result := false;
  if doNormal(5, '') then
  begin
    Result := true;
    if P_BankType = '10' then
    begin
      if getLandiSettlemsg and (Pub_BankPaper <> '1') then
        PrintBankSettlePaper;
    end
    else if P_BankType = '11' then
      PrintBankSettlePaper;
  end;
end;

end.
