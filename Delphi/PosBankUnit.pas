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

//�㽭����-BASE

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
  SendPacketA,RecvPacketA: array[0..65536] of Char;   //64K ISO8583 128��
  i,len,unionlen: Integer;
begin
  Result := '';
  Ret := 0;

  //�Ѱ�ת���ַ�����
  for i := 1 to Length(Packet) do SendPacketA[i - 1] := Packet[i];
  Sock := TMySocket.Create(cuBankSrv, Str2Int(cuBankSrvPort), 500, true);
  //����socket������
  try
    try
      if Sock.FConnect then
      begin
        len := Sock.Write(@SendPacketA, Length(Packet));

        if len = Length(Packet) then
        begin
          if Sock.WaitFor(60000, 0) then //�ȴ���ʱ60��
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
                SetLR('������ͨѶʧ��,���������Ƿ�����!', 2);
              end;
            end
            else
            begin
              Ret := -4;
              SetLR('������ͨѶʧ��,���������Ƿ�����!', 2);
            end;
          end
          else
          begin
            Ret := -3;
            SetLR('��������Ӧ��!', 2);
          end;
        end
        else
        begin
          Ret := -2;
          SetLR('������ͨѶʧ��,���������Ƿ�����!', 2);
        end;
      end
      else
      begin
        Ret := -1;
        SetLR('������ͨѶʧ��,���������Ƿ�����!', 2);
      end;
    except
      Ret := -6;
      SetLR('������ͨѶʧ��,���������Ƿ�����!', 2);
    end;
  finally
    Sock.Free;
  end;
end;

function Pack(InPath, InType: Byte; InCont: string; InID: string = LanDiId): string;  //��װͨ�Žṹ
var
  lSTX,lETX,LEN0,LEN1,lPATH,lTYPE: Char;
  lLEN,lID,lCont,Temp,TempOutStr: String;
  LRC: Byte;
begin
  lSTX := Char($02); //������ʼ

  LEN0 := Char((8 + Length(InCont)) div 256);
  LEN1 := Char((8 + Length(InCont)) mod 256);
  lLEN := LEN0+LEN1;

  lPATH := Char(InPath);
  lTYPE := Char(InType);

  lID := InID;
  lCont := InCont;

  lETX := Char($03); //������ֹ

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
  OutRet := -1;  //�����쳣������Ϊ-1, 2010.07.19
  SetLR('δ֪����!', 2);

  ChinaUnionFlag := false;

  //������Ϣ��
  PinCom.Recv(lSTX, 1, TimeOut);
  if lSTX = Char($02) then
  begin
    PinCom.Recv(LEN0, 1, 1000);
    PinCom.Recv(LEN1, 1, 1000);
    //������
    llCont := Byte(LEN0) * 256 + Byte(LEN1) - 8; //���ĳ���
    Outlen := llCont;   //modify 2010.03.08 ����������
    //����������������
    PinCom.Recv(lPATH, 1, 1000);
    //����Ӧ������
    PinCom.Recv(lTYPE, 1, 1000);
    //����Ψһ��ʶ
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
          SetLR(''); //��ʼ��
          if lPath = Char($05) then //�����������
          begin
            ChinaUnionFlag := true; //���������
            Result := Hex2Str(IntToHex(Outlen, 4)) + lsCont; //8583�����ϳ��Ȱ�ͷ
          end
          else
          begin
            if (lPath = Char($02)) or (lPath = Char($04)) then  //����Ӧ���������Ӧ���
            begin
              if (lsCont[1] = Char($06)) or (lsCont[1] = Char($15)) then
                SetLR(lsCont);
            end;
            Result := lsCont;
          end;
          OutRet := 0;  // �ɹ�������
        end
        else
        begin
          OutRet := -4;
          SetLR('У��MISPOS�豸ͨ�ŽṹLRCʧ��,�����豸�Ƿ�����!', 2);
        end;
      end
      else
      begin
        OutRet := -3;
        SetLR('��ȡMISPOS�豸������ֵֹʧ��,�����豸�Ƿ���������!', 2);
      end;
    end
    else
    begin
      OutRet := -2;
      SetLR('��ȡMISPOS�豸ͨ�ŽṹIDʧ��,�����豸�Ƿ�����!', 2);
    end;
  end
  else
  begin
    OutRet := -5;
    SetLR('��ȡMISPOS�豸������ʼֵʧ��,�����豸�Ƿ���������!', 2);
  end;
end;

procedure SetUnionpayRoute;
var
  Lv_Type,Lv_Result,Lv_ResultStr: String;
begin
  P_CreditPort := Pub_BankPort;
  Lv_Result := LanDiGetCommMode;
  if Lv_Result = 'P' then
    Lv_ResultStr := '�绰��·'
  else if Lv_Result = 'G' then
    Lv_ResultStr := '������·'
  else if Lv_Result = 'R' then
    Lv_ResultStr := 'GPRS';
  if (Lv_Result = 'P') or (Lv_Result = 'R') or (Lv_Result = 'G') then
  begin
    if ShowInputQuery('������ ' + '������·�л�' + ' ���', '��ǰͨѶ��ʽ��' + Lv_ResultStr + '�����������0���绰��·��1��������·��2��GPRS��', 0, 0, Lv_Type) then
    begin
      if Lv_Type = '0' then
      begin
        Lv_ResultStr := '�绰��·';
        Lv_Result := LanDiSetCommMode('P');
      end
      else if Lv_Type = '1' then
      begin
        Lv_ResultStr := '������·';
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
        Lv_Result := '����ʧ��';
      end;
      if Lv_Result = '���׳ɹ�' then
        ShowMessageBox('�ɹ��л���' + Lv_ResultStr + 'ˢ��ģʽ', '��Ϣ', MB_OK + MB_ICONINFORMATION)
      else
        ShowMessageBox('������·�л�ʧ��', '��Ϣ', MB_OK + MB_ICONINFORMATION);
    end;
  end
  else
    ShowMessageBox('��·״̬��ȡʧ��', 'ϵͳ��Ϣ', MB_ICONWARNING);
end;

//�㽭����-PRINT

procedure PrintBankCoupon2(rs: resPos);

  //ȡ������������
  function getBrackets(InStr: string; Mode: String): string;
  var
    i: Integer;
    Temp: string;
    FoundBegin: Boolean;
  begin
    Result := InStr;
    FoundBegin := false;
    Temp := '';
    if Mode = 'Y' then //������
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
  Writeln(f, GetMemo('����������ˢ62������'));
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));

  Writeln(f, StrCenter(format(fmt0, ['��ϲ���н�'+ getBrackets(gBankMemo, 'Y') + 'Ԫȯ!'])));
  Writeln(f, StrCenter(format(fmt1, ['�̻�����', p_Company])));
  Writeln(f, StrCenter(format(fmt1, ['�̻����', cuMerchantID])));
  Writeln(f, StrCenter(format(fmt1, ['�ն˱��', format('%8.8s', [cuTerminalID])])));
  Writeln(f, StrCenter(format(fmt1, ['ˢ������', rs.Cardno])));
  Writeln(f, StrCenter(format(fmt1, ['�� �� ��', gCard])));
  Writeln(f, StrCenter(format(fmt1, ['�н�ʱ��', rs.date + rs.time])));
  Writeln(f, StrCenter(format(fmt1, ['�� �� ��', gRefno])));
  Writeln(f, StrCenter(format(fmt0, [format('%8s: %-12.2f', ['���׽��', strtofloat(rs.amount) / 100])])));

  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt0, ['�ֿ���ǩ��:'])));
  for i := 0 to 1 do Writeln(f, '');
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt0, ['������ȷ����ҽ�ȯ'])));
  Writeln(f, '');
  //
  Writeln(f, '');
  Writeln(f, StrCenter(sline));
  Writeln(f, '   СƱ��: ' + Days + P_Syjh + P_seqno + '  ʱ��:' + sTime);
  Writeln(f, '   ����õ�');
  Writeln(f, '[INTIME1001]    ����ȯ: ��' + getBrackets(gBankMemo, 'Y'));
  Writeln(f, '   ʹ����Ч��:' + getDateTime('4', '') + 'ֹ');
  Writeln(f, '   ������Ʒ,��Ӫҵ��ˡ������,���ר����ʾ');
  Writeln(f, '   ��ȯˡ���һ��ֽ�,������');
  Writeln(f, '   ��' + p_Company + 'ʹ��,����˺����Ч');
  //
  sCouponCode := SetCouponInfo('YL', '0', '����ȯ', '4', sTime, rs.Cardno, rs.BankCode, gRefno, '', '', '', strtofloat(rs.amount) / 100, Str2Float(getBrackets(gBankMemo, 'Y')), 1);
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
    Writeln(f, GetMemo('�ֻ�֧��ǩ����'))
  else
    Writeln(f, GetMemo(P_BankTitle));
  if rePrint = 'Y' then
    Writeln(f, StrCenter('���ش�ӡ��'));
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt1, ['�̻�����', p_Company])));
  Writeln(f, StrCenter(format(fmt1, ['�̻����', cuMerchantID])));
  if P_BankType <> '12' then
    Writeln(f, StrCenter(format(fmt1, ['�ն˱��', format('%8.8s', [cuTerminalID])])));
  if IsPaperSMode then
    Writeln(f, StrCenter(ssline))
  else
    Writeln(f, StrCenter(sline));
  Writeln(f, '   ' + format(fmt3, ['��    ��', rs.Cardno]));

  Writeln(f, StrCenter(format(fmt1, ['�� �� ��', gCard]))); //�����±�׼
  if rs.LandiType = '01' then
    Writeln(f, StrCenter(format(fmt2, ['��������', '����', '�� Ч ��', gExpdate])))
  else if rs.LandiType = '02' then
    Writeln(f, StrCenter(format(fmt2, ['��������', '����', '�� Ч ��', gExpdate])))
  else if rs.LandiType = '03' then
    Writeln(f, StrCenter(format(fmt2, ['��������', '�˻�', '�� Ч ��', gExpdate])))
  else if rs.LandiType = '42' then
    Writeln(f, StrCenter(format(fmt2, ['��������', '����', '�� Ч ��', gExpdate])))
  else if rs.LandiType = '43' then
    Writeln(f, StrCenter(format(fmt2, ['��������', '�˻�', '�� Ч ��', gExpdate])))
  else
    Writeln(f, StrCenter(format(fmt2, ['��������', '����', '�� Ч ��', gExpdate])));
  Writeln(f, StrCenter(format(fmt2, ['��������', rs.date, '����ʱ��', rs.time])));
  Writeln(f, StrCenter(format(fmt2, ['�� �� ��', rs.batchno, '������ˮ', rs.invoice])));

  Writeln(f, StrCenter(format(fmt1, ['�̻���ˮ', gRefno])));
  Writeln(f, StrCenter(format(fmt1, ['�� Ȩ ��', rs.authno])));

  Writeln(f, StrCenter(format(fmt0, [format('%-9s: %-7s', ['MIS���׺�', P_Syjh + P_Seqno])])));
  //����Ǯ���ж�
  if (Trim(rs.WalletType) <> '') and (req.SaleType = 1) then
    Writeln(f, StrCenter(format(fmt0, [format('%8s: %-12.2f', ['���׽��', strtofloat(rs.amount) / 100 + strtofloat(rs.WalletAmt) / 100])])))
  else
    Writeln(f, StrCenter(format(fmt0, [format('%8s: %-12.2f', ['���׽��', strtofloat(rs.amount) / 100])])));

  Writeln(f, StrCenter(format(fmt0, ['�ֿ������֤����:'])));
  if rq.Cardid[0] <> '0' then Writeln(f, StrCenter(format(fmt0, [rq.cardid])));
  if not f_empstr(gBankMemo) then
  begin
    SetLength(FOutStrA, getCharCount(gBankMemo, ';') + 1);
    StrToArrayS(gBankMemo, ';', FOutStrA);
    Writeln(f, '   ��ע: ');
    for i := 0 to High(FOutStrA) do
    begin
      if not f_empstr(FOutStrA[i]) then Writeln(f, '   ' + trim(FOutStrA[i]));
    end;
  end;
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt0, ['�ֿ���ǩ��:'])));
  for i := 0 to 1 do Writeln(f, '');
  if IsPaperSMode then
    Writeln(f, StrCenter(ddline))
  else
    Writeln(f, StrCenter(dline));
  Writeln(f, StrCenter(format(fmt0, ['����ͬ��֧����������'])));
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
    ShowMessageBox('���ÿ�ǩ�����ļ� [' + P_BankPaper + '] ������,����ϵ��Ϣ��!', 'ϵͳ����', MB_ICONSTOP);
end;

procedure PrintBankSettlePaper;   //���ÿ����㵥
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
    title := '�ֻ�֧�����㵥'
  else
    title := '�����̻����㵥';
  Writeln(f, GetMemo(title));
  Writeln(f, '[INTIME9800]');
  Writeln(f, '');
  Writeln(f, getSpace + '����:' + getLocalDate + ' ʱ��:' + FormatDateTime('hh:mm:ss', now));
  if IsPaperSMode then
    Writeln(f, StrCenter(ssline))
  else
    Writeln(f, StrCenter(sline));
  Writeln(f, getSpace + format(fmt1, ['�̻�����', gBankSettle.MchtName]));
  Writeln(f, getSpace + format(fmt1, ['�̻����', gBankSettle.MchtCode]));
  Writeln(f, getSpace + format(fmt1, ['�ն˱��', gBankSettle.TermId]));
  Writeln(f, getSpace + format(fmt1, ['����Ա��', P_gh]));
  Writeln(f, getSpace + format(fmt1, ['�� �� ��', gBankSettle.Batchno]));
  if IsPaperSMode then
    Writeln(f, StrCenter(ssline))
  else
    Writeln(f, StrCenter(sline));
  Writeln(f, getSpace + format(fmt3, ['���ѱ���', Str2Int(gBankSettle.Inbs1)]));
  Writeln(f, getSpace + format(fmt2, ['���ѽ��', Str2Float(gBankSettle.Inje1) / 100]));
  Writeln(f, getSpace + format(fmt3, ['�˻�����', Str2Int(gBankSettle.Inbs2)]));
  Writeln(f, getSpace + format(fmt2, ['�˻����', Str2Float(gBankSettle.Inje2) / 100]));
  if IsPaperSMode then
    Writeln(f, StrCenter(ssline))
  else
    Writeln(f, StrCenter(sline));
  Writeln(f, getSpace + format(fmt2, ['����ܼ�', (Str2Float(gBankSettle.Inje1) - Str2Float(gBankSettle.Inje2)) / 100]));
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

    //��ӡ��Ϣ
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
              StrToArray(res.Bankcode, FOutStrA[i]); //������������
              StrToArray(FBankCode, Copy(FOutStrA[i], 1, 4));
              getTransStr(PChar(g_Path + 'Banks.ini'), FBankCode, gCard);
            end;
            8: StrToArray(res.Cardno, FOutStrA[i]); //����
            10: StrToArray(res.LandiType, FOutStrA[i]); //�豸��������
            11: StrToArray(gExpdate, FOutStrA[i]); //����Ч����
            12: StrToArray(res.Batchno, FOutStrA[i]); //���κ�
            13: StrToArray(res.Invoice, FOutStrA[i]); //��ˮ��
            14:
            begin
              StrToArray(res.Date, Copy(FOutStrA[i], 1, 4)); //��������
              StrToArray(res.Time, Copy(FOutStrA[i], 5, 6)); //����ʱ��
            end;
            15: StrToArray(res.Authno, FOutStrA[i]); //��Ȩ��
            16: StrToArray(gRefno, FOutStrA[i]); //�ο���
            17: StrToArray(res.Amount, FOutStrA[i]); //���׽�ԪΪ��λ��С����2λ
            33:  //��ע
            begin
              if (not f_empstr(FOutStrA[i])) and (P_SaleType = '0') then
              begin
                StrToArray(gBankMemo, FOutStrA[i]);
              end;
            end;
            34: StrToArray(res.CheckSum, FOutStrA[i]); //У����
            41: StrToArray(res.WalletType, FOutStrA[i]); //����Ǯ����������
            42: StrToArray(res.WalletAmt, FOutStrA[i]); //����Ǯ�����׽��
            43: StrToArray(res.WalletSerial, FOutStrA[i]); //����Ǯ����ˮ��
            44: StrToArray(res.WalletRef, FOutStrA[i]); //����Ǯ���ο���
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
      ShowMessageBox(gLR.Hint, '���ÿ���ʾ', MB_ICONWARNING);
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
          StrToArray(res.Bankcode, FOutStrA[i]); //������������
          StrToArray(FBankCode, Copy(FOutStrA[i], 1, 4));
          getTransStr(PChar(g_Path + 'Banks.ini'), FBankCode, gCard);
        end;
        8 + 3: StrToArray(res.Cardno, FOutStrA[i]); //����
        10 + 3: StrToArray(res.LandiType, FOutStrA[i]); //�豸��������
        11 + 3: StrToArray(gExpdate, FOutStrA[i]); //����Ч����
        12 + 3: StrToArray(res.Batchno, FOutStrA[i]); //���κ�
        13 + 3: StrToArray(res.Invoice, FOutStrA[i]); //��ˮ��
        14 + 3:
        begin
          StrToArray(res.Date, Copy(FOutStrA[i], 1, 4)); //��������
          StrToArray(res.Time, Copy(FOutStrA[i], 5, 6)); //����ʱ��
          end;
        15 + 3: StrToArray(res.Authno, FOutStrA[i]); //��Ȩ��
        16 + 3: StrToArray(gRefno, FOutStrA[i]); //�ο���
        17 + 3: StrToArray(res.Amount, FOutStrA[i]); //���׽�ԪΪ��λ��С����2λ
        33 + 3:  //��ע
        begin
          if (not f_empstr(FOutStrA[i])) and (P_SaleType = '0') then
          begin
            StrToArray(gBankMemo, FOutStrA[i]);
          end;
        end;
        34 + 3: StrToArray(res.CheckSum, FOutStrA[i]); //У����
        41 + 3: StrToArray(res.WalletType, FOutStrA[i]); //����Ǯ����������
        42 + 3: StrToArray(res.WalletAmt, FOutStrA[i]); //����Ǯ�����׽��
        43 + 3: StrToArray(res.WalletSerial, FOutStrA[i]); //����Ǯ����ˮ��
        44 + 3: StrToArray(res.WalletRef, FOutStrA[i]); //����Ǯ���ο���
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
      StrToArray(BankTradeInfo.Cardno, res.Cardno);     //����
      StrToArray(BankTradeInfo.DateTime, FormatDateTime('yyyy', now) + StrPas(res.Date) + StrPas(res.Time)); //����ʱ��
      if Trim(BankTradeInfo.DateTime) = FormatDateTime('yyyy', now) then
      begin
        StrToArray(BankTradeInfo.DateTime, FormatDateTime('yyyymmddhhmmss', now));
      end;
      StrToArray(BankTradeInfo.BankCode, res.BankCode); //���к�
      StrToArray(BankTradeInfo.BankName, gCard);        //��������
      StrToArray(BankTradeInfo.Amount, res.Amount);     //���
      StrToArray(BankTradeInfo.PosTrace, res.Invoice);  //������ˮ
      StrToArray(BankTradeInfo.Batchno, res.Batchno);   //���κ�
      StrToArray(BankTradeInfo.Mode, IntToStr(req.SaleType)); //��������
      StrToArray(BankTradeInfo.RspCode, res.RspCode);   //Ӧ����
      StrToArray(BankTradeInfo.RefNum, gRefno);         //�ο���
      StrToArray(BankTradeInfo.CheckSum, res.CheckSum); //У����
      if (Trim(res.WalletType) <> '') and ((req.SaleType = 2) or (req.SaleType = 6)) then
        StrToArray(BankTradeInfo.CommMode, res.WalletType)
      else
        StrToArray(BankTradeInfo.CommMode, '00');     //����Ǯ�����
      if not f_empstr(gBankMemo) then //��ע
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
      StrToArray(BankTradeInfo.Amount, gLR.Amount);     //���
      StrToArray(BankTradeInfo.BankCode, gLR.BankCode); //���к�
      StrToArray(BankTradeInfo.Mode, gLR.Mode); //��������
    end;
  end;

  StrToArray(BankTradeInfo.TermId, cuTerminalID);  //�ն˺�
  StrToArray(BankTradeInfo.MchtCode, cuMerchantID);  //�̻���
  StrToArray(BankTradeInfo.Fphm, P_syjh + P_seqno);  //СƱ����
  StrToArray(BankTradeInfo.Syyh, IntToStr(High(PayA) + 1));  //֧����ʽ�к�
  StrToArray(BankTradeInfo.Storeno, g_Store);  //�ֵ���
  StrToArray(BankTradeInfo.Opertime, FormatDateTime('yyyymmddhhmmss', now)); //����ʱ��

  //��Կ��ź�У����Ϊ��������⴦��
  if f_empstr(BankTradeInfo.Cardno) then
  begin
    StrToArray(BankTradeInfo.Cardno, '000000******0000');
    StrToArray(BankTradeInfo.CheckSum, 'B02132081808B493C61E86626EE6C2E29326A662');
  end;

  BankTradeInfo.Flag := '0';
  AppendDosRecord(@BankTradeInfo, 11);

  //����Ǯ������
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

function getLandiSettlemsg: Boolean;   //��ý�����Ϣ
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

    //������Ϣ
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
            1: gBankSettle.MchtCode := FOutStrA[i];  //�̻�����
            2: gBankSettle.TermId := FOutStrA[i];    //�ն˺�
            3: gBankSettle.MchtName := FOutStrA[i];  //�̻�����
            5: gBankSettle.Batchno := FOutStrA[i];   //���κ�
            6: gBankSettle.DateTime := FOutStrA[i];  //����ʱ��
            8: gBankSettle.Inbs1 := FOutStrA[i];     //���ѱ���
            9: gBankSettle.Inje1 := FOutStrA[i];     //���ѽ��
            10: gBankSettle.Inbs2 := FOutStrA[i];     //�˻�����
            11: gBankSettle.Inje2 := FOutStrA[i];     //�˻����
          end;
          Result := true;
        end;
      except
      end;
    end
  else
  begin
    ShowMessageBox(gLR.Hint, '���ÿ���ʾ', MB_ICONWARNING);
  end;
  finally
    PinCom.Free;
  end;
end;

//�㽭����-FUNC

function LanDiTest: Boolean; //�������ӱ���
var
  Send,Recv,lID,lSendCont: String;
  ret: Integer;
  CUF: Boolean;
begin
  Result := false;
  ret := -1;
  lID := FormatDateTime('hhmmss', now);

  if cuType = $05 then  //�ֻ�֧��
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

  if Result then gLR.Hint := ''; //�����
end;

function LandiPartial: Boolean;  //���ڸ���
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

    //�绰��ģʽ
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

    //����
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

    //�绰��ģʽ
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

function LandiRepeal: Boolean;    //����
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

    //���ѳ���
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

    //�绰��ģʽ
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

function LandiRecall: Boolean;    //�����˻�
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
  req.SaleType := 6; //�����˻�

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //�˻�
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

    //�绰��ģʽ
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

    //����ѯ
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

    //�绰��ģʽ
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

function LandiSettle: Boolean; //����
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

    //�绰��ģʽ
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

function LanDiGetCommMode: String; //��ȡ���ϼ���ͨѶģʽ G:GPRS P:�绰
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

function LanDiSetCommMode(MsgStr: String): String; //�ı����ϼ���ͨѶģʽ G:GPRS P:�绰
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

    //����Ϣ
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

//�㽭����-UNIONPAYWALLET

function WalletConsume: Boolean;  //Ǯ������
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

    //����
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

    //�绰��ģʽ
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

function WalletRepeal: Boolean;  //Ǯ������
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

    //���ѳ���
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

    //�绰��ģʽ
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

function WalletRecall: Boolean;  //Ǯ���˻�
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
  req.SaleType := 6; //�����˻�

  if not LanDiTest then Exit;

  try
    PinCom := TMyComm.Create(P_CreditPort, 9600, 'N', 8, 1, false);

    //�˻�
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

    //�绰��ģʽ
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

  if lResult = 0 then  //���׳ɹ�
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
    FMsg('', '��ˢ��(���п�)', 0, false);
    MsgForm.Refresh;
    doWallet(req.SaleType, r.Mode);
    if res.Ok = 0 then
    begin
      MsgForm.Close;
      ShowMessageBox(res.Errmsg, '������Ϣ��ʾ', MB_ICONINFORMATION + MB_OK);
    end
    else
    begin
      MsgForm.Close;
      try
        StrCopy(PayA[Index].PayID, res.Cardno);
      except
        on E: Exception do Debug('���ÿ����Ÿ�ֵʧ��[' + IntToStr(Index) + ']:' + E.Message + IntToStr(E.HelpContext));
      end;
      result := true;
      try
        StrToArray(req.Mode, IntToStr(index + 1));
        //�������ÿ���Ϣ
        SetBankTradeInfo;
        //��ӡ���ÿ�ǩ����
        if Pub_BankPaper <> '1' then
          PrintBankPaper(req, res, 1, 'N');
        //��ӡ���п�������ҽ���
        if P_BankCoupon = 'Y' then
          PrintBankCoupon2(res);
      except
        Debug('���ÿ�ǩ������ӡʧ��');
      end;
    end;
  except
    on E: Exception do Debug('���ÿ��������������쳣[' + E.Message + ']');
  end;
end;

//����-ͨ��

function LoadPosInf: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'PosInf.dll'
  else
    BankDLL := P_BankDLL;
  PosInfHandle := LoadLibrary(PChar(BankDLL)); //��̬����DLL������������
  if PosInfHandle <> 0 then //�������ɹ����ȡ������ַ
  begin
    @EmvBank := GetProcAddress(PosInfHandle, 'bankall');
    if (@EmvBank = nil) then
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreePosInf;
begin
  FreeLibrary(PosInfHandle); //��������ջ�DLLռ�õ���Դ
end;

//�人���У��������ģ�

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
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeKeeperClientICBC;
begin
  FreeLibrary(KeeperClientHandle); //��������ջ�DLLռ�õ���Դ
end;

//�ߺ����У��������ģ�

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
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeKeeperClientCCB;
begin
  FreeLibrary(KeeperClientHandle); //��������ջ�DLLռ�õ���Դ
end;

//����ũ�С��ٺ�ũ�С��ɶ����У��Ͼ���ʯ��

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
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeSoftposDll;
begin
  FreeLibrary(SoftPosHandle); //��������ջ�DLLռ�õ���Դ
end;

//��������

function LoadHZBankDll: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'hzmispos.dll'
  else
    BankDLL := P_BankDLL;
  HZBankHandle := LoadLibrary(PChar(BankDLL)); //��̬����DLL������������
  if HZBankHandle <> 0 then //�������ɹ����ȡ������ַ
  begin
    @HZBank := GetProcAddress(HZBankHandle, 'CreditTransUMS');
    if (@HZBank = nil) then
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeHZBankDll;
begin
  FreeLibrary(HZBankHandle); //��������ջ�DLLռ�õ���Դ
end;

//��������

function LoadICBCDll: Boolean;
var
  BankDLL: String;
begin
  Result := false;
  if P_BankDLL = '' then
    BankDLL := 'MposCore.dll'
  else
    BankDLL := P_BankDLL;
  ICBCHandle := LoadLibrary(PChar(BankDLL)); //��̬����DLL������������
  if ICBCHandle <> 0 then //�������ɹ����ȡ������ַ
  begin
    @MisTranSTD := GetProcAddress(ICBCHandle, 'DoICBCZJMisTranSTD');
    if (@MisTranSTD = nil) then
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING)
    else
      Result := true;
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeICBCDll;
begin
  FreeLibrary(ICBCHandle); //��������ջ�DLLռ�õ���Դ
end;

//�������ţ���ɽ���У�
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
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeSingLeeDll;
begin
  FreeLibrary(SingLeeHandle);
end;

//������ʶ������ũ�У�
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
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeEchaseDll;
begin
  FreeLibrary(ChaseHandle);
end;

//�Ͼ��𿵣����ݹ��У�
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
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeRiComDll;
begin
  FreeLibrary(RiComHandle);
end;

//�Ϻ�ɼ�£�����ũ�У�
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
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
end;

procedure FreeESandDll;
begin
  FreeLibrary(ESandHandle);
end;

//�������񣨲��ϣ�
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
      ShowMessageBox('��ʼ������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
  end
  else
    ShowMessageBox('��������������ʧ��,���ÿ����ײ�������ִ��', 'ϵͳ����', MB_ICONWARNING);
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

    if lResult = 0 then  //���׳ɹ�
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

      if lResult = 0 then  //���׳ɹ�
      begin
        res.Ok := 1;
        if mode <> 3 then      //������ӡ��Ϣ
        begin
          FOutStrA := nil;
          SetLength(FOutStrA, getCharCount(gHZBankOut.print_msg, Char($1C)) + 1);
          StrToArrayS(gHZBankOut.print_msg, Char($1C), FOutStrA);
          if gHZBankIn.trans = 'O' then
          begin
            gBankSettle.MchtName := FOutStrA[2];  //�̻�����
            gBankSettle.MchtCode := FOutStrA[0];  //�̻�����
            gBankSettle.TermId := FOutStrA[1];  //�ն˺�
            gBankSettle.Batchno := FOutStrA[4];  //���κ�
            gBankSettle.DateTime := FOutStrA[5];  //����ʱ��
            gBankSettle.Inbs1 := FOutStrA[7];  //���ѱ���
            gBankSettle.Inje1 := FOutStrA[8];  //���ѽ��
            gBankSettle.Inbs2 := FOutStrA[9];  //�˻�����
            gBankSettle.Inje2 := FOutStrA[10];  //�˻����
          end
          else
          begin
            cuMerchantID := FOutStrA[0];         //�̻���
            cuTerminalID := FOutStrA[1];         //�ն˺�
            StrToArray(res.Date, Copy(FOutStrA[13], 1, 4)); //��������
            StrToArray(res.Time, Copy(FOutStrA[13], 5, 6)); //����ʱ��
            StrToArray(res.Invoice, FOutStrA[12]);  //��ˮ��
            StrToArray(res.Batchno, FOutStrA[11]);  //���κ�
            StrToArray(res.Authno, FOutStrA[14]);  //��Ȩ��
            StrToArray(res.Cardno, FOutStrA[7]); //����
            StrToArray(res.Amount, FOutStrA[16]);  //���
            StrToArray(res.RspCode, gHZBankOut.resp_code);  //�óɹ�������
            StrToArray(res.LandiType, FOutStrA[9]);  //�������ͱ�־
            StrtoArray(gCard, ''); //���к�
            StrtoArray(gExpdate, FOutStrA[10]);  //ʧЧ����
            StrToArray(gRefno, FOutStrA[15]);  //�ο���
            if Length(FOutStrA) > 32 then
              StrToArray(gBankMemo, FOutStrA[32]);  //��ע
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
        4: id := '4005';                        //�ش�ӡ4005���ĵ�δд
        5: goto labelEnd;
      end;
      outChar := MisTranSTD(PWideChar(@id), PWideChar(@preinput), PWideChar(@rsv), PWideChar(@rsv), PWideChar(@rsv));
      sTemp := outChar;
      StrCopy(PChar(@gICBCOut), PChar(sTemp));
      if gICBCOut.RspCode = '00' then lResult := 0;

      if lResult = 0 then  //���׳ɹ�
      begin
        res.Ok := 1;
        StrToArray(res.Date, Copy(gICBCOut.ChargeDate, 5, 4)); //��������
        StrToArray(res.Time, gICBCOut.ChargeTime); //����ʱ��
        StrToArray(res.Invoice, gICBCOut.Trace);  //��ˮ��
        StrToArray(res.Batchno, gICBCOut.BatchNo);  //���κ�
        StrToArray(res.Authno, gICBCOut.AuthId); //��Ȩ��
        StrToArray(res.Cardno, gICBCOut.Cardno); //����
        StrToArray(res.Amount, gICBCOut.Amount);  //���
        StrToArray(res.BankCode, gICBCOut.BankCode); //���к�
        StrToArray(res.RspCode, gICBCOut.RspCode);  //�óɹ�������
        cuTerminalID := PChar(Copy(gICBCOut.TermId, Length(gICBCOut.TermId) - 9, 8));    //�ն˺�
        cuMerchantID := PChar(Copy(gICBCOut.Memo, Pos(':', gICBCOut.Memo) + 1, 15));     //�̻���

        //��������
        if id = '1001' then
          res.LandiType := '01'
        else if id = '1101' then
          res.LandiType := '02'
        else if id = '1102' then
          res.LandiType := '03';
        StrtoArray(gCard, gICBCOut.BankCode); //���к�
        StrtoArray(gExpdate, gICBCOut.Expr); //ʧЧ����
        StrToArray(gRefno, gICBCOut.RefNo); //�ο���
        StrToArray(gBankMemo, '�ն˱��: ' + PChar(Copy(gICBCOut.TermId, 1, Length(gICBCOut.TermId))));  //��ע�ֶδ��ն˺�
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

      if lResult = 0 then  //���׳ɹ�
      begin
        res.Ok := 1;
        StrtoArray(res.Date, Copy(sticbcmis_res.TransDate, 5, 4)); //��������
        StrtoArray(res.Time, Copy(sticbcmis_res.TransTime, 1, 6)); //����ʱ��
        StrtoArray(res.Invoice, sticbcmis_res.TerminalTraceNo); //������ˮ
        StrtoArray(res.Batchno, sticbcmis_res.TerminalBatchNo); //���κ�
        StrtoArray(res.Authno, sticbcmis_res.AuthNo); //��Ȩ��
        StrtoArray(res.Cardno, sticbcmis_res.CardNo); //����
        StrtoArray(res.Amount, sticbcmis_res.Amount); //���
        StrtoArray(res.RspCode, sticbcmis_res.RspCode); //Ӧ����
        StrtoArray(res.LandiType, sticbcmis_res.TransType); //�豸��������

        StrtoArray(gCard, ''); //���к�
        StrtoArray(gRefno, sticbcmis_res.ReferNo); //ϵͳ���ٺ�
        StrtoArray(gExpdate, sticbcmis_res.ExpDate); //ʧЧ����
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

      if lResult = 0 then  //���׳ɹ�
      begin
        res.Ok := 1;
        StrtoArray(res.Date, Copy(stccbmis_res.TransDate, 5, 4)); //��������
        StrtoArray(res.Time, stccbmis_res.TransTime); //����ʱ��
        StrtoArray(res.Invoice, stccbmis_res.posTraceNum); //������ˮ
        StrtoArray(res.Batchno, stccbmis_res.batchNum); //���κ�
        StrtoArray(res.Authno, stccbmis_res.authorNum); //��Ȩ��
        StrtoArray(res.Cardno, stccbmis_res.transCardNum); //����
        StrtoArray(res.Amount, stccbmis_res.transAmount); //���
        StrtoArray(res.RspCode, stccbmis_res.rspCode); //Ӧ����
        StrtoArray(res.LandiType, stccbmis_res.transType); //�豸��������

        StrtoArray(gCard, ''); //���к�
        StrtoArray(gRefno, stccbmis_res.hostTrace); //ϵͳ���ٺ�
        StrtoArray(gExpdate, stccbmis_res.expDate); //ʧЧ����
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

      if lResult = 0 then  //���׳ɹ�
      begin
        res.Ok := 1;
        StrToArray(res.LandiType, gEmvRequest.trans);
        Inc(res.LandiType[1]);                          //��������
        StrtoArray(res.Date, gEmvResponse.ChargeDate);  //����
        StrtoArray(res.Time, gEmvResponse.ChargeTime);  //ʱ��
        StrtoArray(res.Invoice, gEmvResponse.trace);  //��ˮ��
        StrtoArray(res.Batchno, gEmvResponse.BatchNo);  //���κ�
        StrtoArray(res.Authno, gEmvResponse.AuthId);  //��Ȩ��
        StrtoArray(res.Cardno, gEmvResponse.card_no); //����
        StrtoArray(res.Amount, gEmvResponse.amount);  //���
        StrtoArray(res.BankCode, gEmvResponse.bank_code);  //���к�
        StrToArray(res.RspCode, gEmvResponse.resp_code);  //�óɹ�������

        getTransStr(PChar(g_path + 'Banks.ini'), res.BankCode, gCard); //������
        StrtoArray(gRefno, gEmvResponse.RefNo); //ϵͳ���ٺ�
        StrtoArray(gExpdate, gEmvResponse.expr); //ʧЧ����
        Result := true;
      end
      else
      begin
        res.Ok := 0;
        fillchar(gRescode, length(gRescode),char(0));
        Move(gEmvResponse.resp_code, gRescode, 2);
        if getTransStr(PChar(g_path + 'Rsp.ini'), gRescode, res.Errmsg) <> 0 then
          StrCopy(res.Errmsg, '����������δ֪����!');
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

      if lResult = 0 then  //���׳ɹ�
      begin
        res.Ok := 1;
        StrToArray(res.Date, gStrOut.txn_date); //��������
        StrToArray(res.Time, gStrOut.txn_time); //����ʱ��
        StrToArray(res.Invoice, gStrOut.pos_systrace);  //��ˮ��
        StrToArray(res.Cardno, gStrOut.pan); //����
        StrToArray(res.Amount, gStrOut.tr_amt);  //���
        StrToArray(res.RspCode, gStrOut.rc);  //�óɹ�������
        if gStrOut.txn_no = 'C' then  //�������ͱ�־
          StrToArray(res.LandiType, '01')
        else if gStrOut.txn_no = 'D' then
          StrToArray(res.LandiType, '02')
        else if gStrOut.txn_no = 'R' then
          StrToArray(res.LandiType, '03')
        else
          StrToArray(res.LandiType, '00');

        StrtoArray(gCard, ''); //���к�
        StrToArray(gRefno, gStrOut.RRN);  //�ο���
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
          StrCopy(res.Errmsg, '����������δ֪����!');
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
        res.RspCode := '00';                                          //Ӧ����
        StrToArray(res.LandiType, gXLCCBOut.transCode);               //��������
        StrToArray(res.Date, Copy(gXLCCBOut.bankSrvDate, 5, 4));      //��������
        StrToArray(res.Time, gXLCCBOut.bankSrvTime);                  //����ʱ��
        StrToArray(res.Amount, gXLCCBOut.transAmount);                //���׽��
        StrToArray(res.Invoice, gXLCCBOut.pos_trace);                 //�̻���ˮ��
        StrToArray(res.Batchno, gXLCCBOut.batchNo);                   //���κ�
        StrToArray(res.Authno, gXLCCBOut.authorNo);                   //��Ȩ��
        StrToArray(res.BankCode, gXLCCBOut.bankCode);                 //���к�
        StrToArray(res.Cardno, gXLCCBOut.cardNo);                     //����

        StrToArray(gCard, gXLCCBOut.cardNo);                          //����
        StrToArray(gExpdate, gXLCCBOut.expDate);                      //��Ч��
        StrToArray(gRefno, gXLCCBOut.refNo);                          //�ο���
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
        StrToArray(res.RspCode, gChaseOut.respCode);                //������
        StrToArray(res.LandiType, gChaseOut.transType);             //��������
        StrToArray(res.Cardno, gChaseOut.cardNo);                   //����
        StrToArray(gCard, gChaseOut.cardNo);
        if UpperCase(Copy(gChaseOut.memo, 1, 3)) = 'VOU' then
        begin
          stR := SplitString(PChar(@gChaseOut.memo), '|');          //ƾ֤��Ϣ��
          StrToArray(res.Date, Copy(stR.Strings[12], 1, 4));        //��������
          StrToArray(res.Time, Copy(stR.Strings[12], 5, 6));        //����ʱ��
          StrToArray(res.Invoice, stR.Strings[11]);                 //��ˮ��
          StrToArray(res.Batchno, stR.Strings[10]);                 //���κ�
          StrToArray(res.Authno, stR.Strings[13]);                  //��Ȩ��
          dTemp := (StrToFloatDef(stR.Strings[15], 0) + StrToFloatDef(stR.Strings[20], 0)) / 100;
          StrToArray(res.Amount, dtos(dTemp));                      //���׽��

          StrToArray(gBankMemo, stR.Strings[16]);                   //��ע
          StrToArray(gExpdate, stR.Strings[9]);                     //��Ч��
          StrToArray(gRefno, stR.Strings[14]);                      //�ο���
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
      //��ɾ��toprint.txt
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
            StrToArray(res.RspCode, gRiComOut.respCode);                //Ӧ����
            StrToArray(res.Amount, gRiComOut.amount);                   //���׽��
            StrToArray(res.Cardno, gRiComOut.cardno);                   //����
            StrToArray(res.LandiType, gRiComIn.transType);              //��������
            StrToArray(res.Invoice, gRiComOut.batchNo);                 //ƾ֤��
            StrToArray(res.Date, Copy(gRiComOut.operdate, 5, 4));       //��������
            StrToArray(res.Time, gRiComOut.opertime);                   //����ʱ��

            StrToArray(gCard, gRiComOut.cardbank);                      //������
            StrToArray(gRefno, gRiComOut.index);                        //������

            if mode = 4 then
            begin
              StrToArray(res.Amount, gRiComIn.amount);                   //���׽��
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
        StrToArray(res.RspCode, gESandOut.ResponseCode);        //Ӧ����
        StrToArray(res.LandiType, gESandOut.TransType);         //��������
        StrToArray(res.Amount, gESandOut.Amount);               //���׽��
        StrToArray(res.Cardno, gESandOut.CardNo);               //����
        StrToArray(res.BankCode, gESandOut.BankNo);             //���к�
        StrToArray(res.Date, Copy(gESandOut.TransDate, 5, 4));  //��������
        StrToArray(res.Time, gESandOut.TransTime);              //����ʱ��
        StrToArray(res.Authno, gESandOut.Auth_Code);            //��Ȩ��
        StrToArray(res.Batchno, gESandOut.SellteNum);           //���κ�
        StrToArray(res.Invoice, gESandOut.CashTraceNo);         //������ˮ��

        StrToArray(gExpdate, gESandOut.Exp_Date);               //��Ч����
        StrToArray(gRefno, gESandOut.SysRefNo);                 //�ο���
        StrToArray(gCard, gESandOut.BankNo);                    //���д���
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
        if mode in [1, 2] then       //���ѡ�����
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
    Result := doNormalUmsUnion(mode, flag)     //��������
  else if P_BankType = '7' then
    Result := doNormalESand(mode, flag)  //�Ϻ�ɼ�£�����ũ�У�
  else if P_BankType = '10' then
    result := doNormalLandi(mode, flag) //��̩-ͨ�ã����ϡ��ٸ���
  else if P_BankType = '11' then
    result := doNormalHZBank(mode, flag)  //��������
  else if P_BankType = '12' then
    result := doNormalICBC(mode, flag)  //��������
  else if P_BankType = '15' then
    result := doNormalRiCom(mode, flag)  //�Ͼ��𿵣����ݹ��У�
  else if P_BankType = '17' then
    result := doNormalKeeperClientCCB(mode, flag) //�������ģ��ߺ����У�
  else if P_BankType = '18' then
    result := doNormalKeeperClientICBC(mode) //�������ģ��人���У�
  else if P_BankType = '19' then
    Result := doNormalSingLee(mode, flag)  //�������ţ���ɽ���У�
  else if P_BankType = '20' then
    Result := doNormalEChase(mode, flag)  //������ʶ������ũ�У�
  else if P_BankType = '21' then
    result := doNormalEmv(mode, flag) //����-ͨ�ã�DLL��
  else if P_BankType = '22' then
    result := doNormalYS(mode, flag) //�Ͼ���ʯ������ũ�С��ٺ�ũ�С��ɶ����У�
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
    FMsg('', '��ˢ��(���п�)', 0, false);
    MsgForm.Refresh;
    doNormal(req.SaleType, r.Mode);
    if res.Ok = 0 then
    begin
      MsgForm.Close;
      ShowMessageBox(res.Errmsg, '������Ϣ��ʾ', MB_ICONINFORMATION + MB_OK);
    end
    else
    begin
      MsgForm.Close;
      try
        StrCopy(PayA[Index].PayID, res.Cardno);
      except
        on E: Exception do Debug('���ÿ����Ÿ�ֵʧ��[' + IntToStr(Index) + ']:' + E.Message + IntToStr(E.HelpContext));
      end;
      result := true;
      try
        StrToArray(req.Mode, IntToStr(index + 1));
        //�������ÿ���Ϣ
        SetBankTradeInfo;
        //��ӡ���ÿ�ǩ����
        if Pub_BankPaper <> '1' then
          PrintBankPaper(req, res, 1, 'N');
        //��ӡ���п�������ҽ���
        if P_BankCoupon = 'Y' then
          PrintBankCoupon2(res);
      except
        Debug('���ÿ�ǩ������ӡʧ��');
      end;
    end;
  except
    on E: Exception do Debug('���ÿ��������������쳣[' + E.Message + ']');
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
