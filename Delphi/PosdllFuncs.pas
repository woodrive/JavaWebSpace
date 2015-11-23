unit PosdllFuncs;

interface

uses
  Windows, Classes, SysUtils, StrUtils, Dialogs, Printers, Graphics, Math, Forms;

type
  pPTIMAGESTRUCT = ^PTIMAGESTRUCT;
  PTIMAGESTRUCT = record
    dwWidth       : DWORD;    //The width of the image in pixels.
    dwHeight      : DWORD;    //The height of the image in pixels.
    pBits         : PByte;    //Pointer to the image data.
    pPalette      : PByte;    //Pointer to the palette data (RGBQUAD)for 1,4,8 bit image.
    wBitsPerPixel : Smallint; //Number of bits per pixel.
  end;

type
  pPTQRENCODESTRUCT = ^PTQRENCODESTRUCT;
  PTQRENCODESTRUCT = record
    pData        : PChar;    //Pointer to the data to be encoded.
    nDataLength  : Integer;  //Length of the data in bytes.
    wVersion     : Smallint; //The version of the QR Code.
    wMaskNumber  : Smallint; //The mask number of the QR Code.
    wEccLevel    : Smallint; //Determines the ECC level for encoding a QR Code symbol.
    wModule      : Smallint; //The smallest element size in pixels.
    wGroupTotal  : Smallint; //The number of symbols that belong to the group.
    wGroupIndex  : Smallint; //The index of the symbol in the group
    wLeftSpace   : Smallint; //The left   space of the symbol in pixels while generating Image.
    wRightSpace  : Smallint; //The right  space of the symbol in pixels while generating Image.
    wTopSpace    : Smallint; //The top    space of the symbol in pixels while generating Image.
    wBottomSpace : Smallint; //The bottom space of the symbol in pixels while generating Image.
  end;

type
  //SNBC - POSDLL.dll
	TPOS_Open = function (pszPortName: pchar; nComBaudrate: integer; nComDataBits: integer; nComStopBits: integer; nComParity: Integer; nComFlowControl: Integer): Integer; stdcall;
	TPOS_Close = function (): Integer; stdcall;
	TPOS_FeedLine = function (): Integer; stdcall;
	TPOS_SetLineSpacing = function (nDistance: integer): integer; stdcall;
	TPOS_CutPaper = function (nMode: integer; nDistance: integer): integer; stdcall;
	TPOS_S_TextOut = function (pszString: pchar; nOrgx: integer; nWidthTimes: integer; nHeightTimes: integer; nFontType: integer; nFontStyle: integer): integer; stdcall;
	TPOS_S_SetBarcode = function (pszInfo: pchar; nOrgx: integer; nType: integer; nWidthX: integer; nheight: integer; nHriFontType: integer; HriFontPosition: integer; nBytesOfInfo: integer): integer; stdcall;
	TPOS_WriteFile = function (hPort: Integer; pszData: PChar; nBytesToWrite: Integer): Integer; stdcall;
  TPOS_Raster_DownloadAndPrintBmpEx = function (pszPath: PChar; nOrgx, nWidthMulti, nHeightMulti, nDensity: Integer): Integer; stdcall;
  //Zonerich - ZQPortDll.dll
  TIsConnect = Function (strPort: LPCSTR): boolean; stdcall;
  TSendData = Function (strPort: LPCSTR; psz: LPCSTR; nLen: Integer): Integer; stdcall;
  TGetUSBPort = Function (): Integer; stdcall;
  TClosePort = Function (strPort: LPCSTR): boolean; stdcall;
  TPrintQRCode = Function (strPort: LPCSTR; nMode: Integer; psz: LPCSTR; nLen: Integer ): Integer; stdcall;
  TPrintBarcode = Function (strPort: LPCSTR; Data:LPCSTR; DataSize: Integer; Symbology: Integer; Height: Integer; Width: Integer; Alignment: Integer; TextPosition: Integer): Integer; stdcall;
  TPrintBmp =  Function (strPort, szFileName: LPCSTR; nType: Integer): Integer; stdcall;
  //Windows - PtImageRW.dll
  TPtInitImage = procedure (pImage: pPTIMAGESTRUCT); stdcall;
  TPtSaveImage = Function (fileName: String; pImage: pPTIMAGESTRUCT): Integer; stdcall;
  TPtFreeImage = procedure (pImage: pPTIMAGESTRUCT); stdcall;
  //Windows - PtQREncode.dll
  TPtQREncodeInit = procedure (pEncode: pPTQRENCODESTRUCT); stdcall;
  TPtQREncode = function (pEncode: pPTQRENCODESTRUCT; pImage: pPTIMAGESTRUCT): Integer; stdcall;
  //Windows - BCEncode.dll
  TMakeBarCode = function (nBtype: Integer; lpszText: AnsiString; nNarrow: Integer; nWide: integer; nHeight: Integer; nRotate: Integer; nReadable: Integer; err:DWORD): HBITMAP; stdcall;
  TMakeBarcodeBmpFile = procedure (lpszFileName: String; lDpi: DWORD; nBtype: Integer; lpszText: AnsiString; nNarrow: Integer; nWide: integer; nHeight: Integer; nRotate: Integer; nReadable: Integer; err:DWORD); stdcall;

Const
  POS_SUCCESS                = 1001;
  POS_FAIL                   = 1002;
	POS_FONT_TYPE_STANDARD     = 0;
	POS_FONT_TYPE_COMPRESSED   = 1;
	POS_FONT_STYLE_NORMAL      = $0;
	POS_CUT_MODE_FULL          = 0;
	POS_CUT_MODE_FULL_EX       = 2;
	POS_CUT_MODE_PARTIAL_EX    = 3;
	POS_BARCODE_TYPE_JAN13     = $43;
	POS_BARCODE_TYPE_CODE128   = $49;
	POS_HRI_POSITION_NONE      = $0;
	POS_HRI_POSITION_BELOW     = $2;
  POS_BITMAP_PRINT_NORMAL         = 0;
	POS_BITMAP_PRINT_DOUBLE_WIDTH   = 1;
	POS_BITMAP_PRINT_DOUBLE_HEIGHT  = 2;
	POS_BITMAP_PRINT_QUADRUPLE      = 3;

Const
  PT_QRENCODE_SUCCESS = $00000001; //An operation is successful.
  PT_QR_VERSION_AUTO  = $0000;     //Determine the version by the engine,then use the smallest version that can contain the data.
  PT_QR_ECCLEVEL_L    = $0001;     //Use ECC level L. (7% )
  PT_QR_ECCLEVEL_M    = $0000;     //Use ECC level M. (15%)
  PT_QR_ECCLEVEL_Q    = $0003;     //Use ECC level Q. (25%)
  PT_QR_ECCLEVEL_H    = $0002;     //Use ECC level H. (30%)

var
  POSDLLHandle: THandle;
  ZQPortDllHandle: THandle;
  BCEncodeHandle: THandle;
  PtImageRWHandle: THandle;
  PtQREncodeHandle: THandle;
  POS_Open: TPOS_Open;
  POS_Close: TPOS_Close;
  POS_FeedLine: TPOS_FeedLine;
  POS_SetLineSpacing: TPOS_SetLineSpacing;
  POS_CutPaper: TPOS_CutPaper;
  POS_S_TextOut: TPOS_S_TextOut;
  POS_S_SetBarcode: TPOS_S_SetBarcode;
  POS_WriteFile: TPOS_WriteFile;
  POS_Raster_DownloadAndPrintBmpEx: TPOS_Raster_DownloadAndPrintBmpEx;
  IsConnect: TIsConnect;
  SendData: TSendData;
  GetUSBPort: TGetUSBPort;
  ClosePort: TClosePort;
  PrintQRCode: TPrintQRCode;
  PrintBarcode: TPrintBarcode;
  PrintBmp: TPrintBmp;
  MakeBarCode: TMakeBarCode;
  MakeBarcodeBmpFile: TMakeBarcodeBmpFile;
  PtInitImage: TPtInitImage;
  PtSaveImage: TPtSaveImage;
  PtFreeImage: TPtFreeImage;
  PtQREncodeInit: TPtQREncodeInit;
  PtQREncode: TPtQREncode;

  procedure CreateQRCode(ACode: string; AVersion, AEccLevel, AModule: SmallInt);
  procedure sPrint(FileName: string; sPrinter: Integer; Port: string; Baud: Integer; RePrint: String);

implementation

uses Definition, BaseUnit, PosClassUnit;

function DecToStr(InStr: ShortString): String;
var
  tempStr: ShortString;
  i,Len: Integer;
  b: Byte;
begin
  Result := '';
  tempStr := trim(InStr);
  Len := Length(tempStr);
  if (Len mod 2) = 1 then
  begin
    tempStr := tempStr + ' ';
    Inc(Len);
  end;
  try
    for i := 1 to Len do
    begin
      if (i mod 2)=0 then
      begin
        b := StrToInt(Copy(tempStr, i - 1, 2));
        Result := Result + Char(b);
      end
    end;
  except
  end;
end;

procedure CreateQRCode(ACode: string; AVersion, AEccLevel, AModule: SmallInt);
var
  ret: integer;
  m_image: PTIMAGESTRUCT;
  m_encode: PTQRENCODESTRUCT;
begin
  PtInitImage(@m_image);
  PtQREncodeInit(@m_encode);

  m_encode.pData := pChar(ACode);
  m_encode.nDataLength := lstrlen(m_encode.pData);
  m_encode.wVersion := AVersion;
  m_encode.wEccLevel := AEccLevel;
  m_encode.wModule := AModule;
  m_encode.wLeftSpace := 0;
  m_encode.wRightSpace := 0;
  m_encode.wTopSpace := 0;
  m_encode.wBottomSpace := 0;

  ret := PtQREncode(@m_encode, @m_image);

  if FileExists(g_path + 'QRCode.bmp') then
    DeleteFile(g_path + 'QRCode.bmp');
  If ret = PT_QRENCODE_SUCCESS Then
    PtSaveImage(g_path + 'QRCode.bmp', @m_image);

  PtFreeImage(@m_image);
end;

function ParsePixel(InPixel: Integer): String;
var
  Bit: array[0..7] of Integer;
  temp,i: Integer;
begin
  Result := '00000000'; //白点

  Bit[0] := 1;
  Bit[1] := 2;
  Bit[2] := 4;
  Bit[3] := 8;
  Bit[4] := 16;
  Bit[5] := 32;
  Bit[6] := 64;
  Bit[7] := 128;

  temp := InPixel;
  if (temp > 0) and (temp <= 255) then
  begin
  while temp >= 0 do
    begin
      for i := 7 downto 0 do
      begin
        if temp >= Bit[i] then
        begin
          temp := temp - Bit[i];
          Result := Copy(Result, 1, 7 - i) + '1' + Copy(Result, 8 - i + 1, i);
          if temp = 0 then temp := -1;
          Break;
        end;
      end;
    end;
  end;
end;

function BitMapToNVPrinterData(FileName: string): string;
var
  BM: TBitmap;
  i, j, k, w, h, L9, b: integer;
  s, s0, s1, Data: string;
  ii: array of array of integer;
begin
  Result := '';
  if not FileExists(FileName) then Exit;  //文件不存在则退出

  BM := TBitmap.Create;
  try
    s := '';
    s0 := '';
    s1 := '';
    BM.LoadFromFile(FileName);

    w := BM.Width Div 8;
    h := BM.Height Div 8;

    SetLength(Data, w);
    //EPSON,HISENSE
    SetLength(ii, 8 * w, 8 * h);

    for L9 := 0 to BM.Height - 1 do
    begin
      Move(BM.ScanLine[L9]^, Data[1], w);

      for i := 1 to w do
      begin
        b := byte(Data[i]) xor $FF;
        s := s + char(b);
      end;
    end;

    //
    for L9 := 0 To 8 * h - 1 Do
    begin
      Move(BM.ScanLine[L9]^, Data[1], w);
      for i := 1 to w do
      begin
        b := byte(Data[i]) xor $FF;
        s0 := ParsePixel(b);
        for j := 1 to 8 do
        begin
          ii[8 * (i - 1) + j - 1, L9] := StrToInt(s0[j]);
        end;
      end;
    end;
    for i := 1 to 8 * w do
    begin
      for j := 1 to h do
      begin
        b := 0;
        for k := 7 downto 0 do b := b + Trunc(IntPower(2, k)) * ii[i - 1, 8 * (j - 1) + 7 - k];
        s1 := s1 + Char(StrToInt('$' + IntToHex(b, 2)));
      end;
    end;
    //Hex		1C		71		n		[xL xH yL yH d1...dk]1 ... [xL xH yL yH d1...dk]n
    //https://reference.epson-biz.com/modules/ref_escpos/index.php?content_id=90
    //char(strtoint('$' + inttohex(integer('['), 2)))
    s1 := Char(w mod 256) + Char(w div 256) + Char(h mod 256) + Char(h div 256) + s1;
    Result := s1;
  finally
    BM.Free;
  end;

end;

procedure sPrint(FileName: string; sPrinter: Integer; Port: string; Baud: Integer; RePrint: String);
{
  打印机型号 Printer：
  0:  SNBC 新北洋
  1:  Zonerich 中崎
  2:  Windows 驱动
  =========================
  打印文件特殊行命令注释:
  [INTIMExxxx]data
  -------------------------
  [INTIME0001] —图片原型
  [INTIME0002] —图片放大
  [INTIME1001] —字体放大
  [INTIME9800] —重打印
  [INTIME9801] —13码
  [INTIME9802] —128码
  [INTIME9811] —QRCode
  [INTIME9901] —切纸半切
  [INTIME9902] —切纸全切
}
var
  IsLPT: Boolean;
  f, fp: textfile;
  temp,KeyStr,KeyData,SpecStr,ImgStr: string;
  iHandle,i,txtRow,txtRowCount,prnStart,prnEnd: Integer;
  sList: TStringlist;
  Lv_Length,Lv_TextHeight,Lv_Start,Lv_End,Lv_ExtStart,Lv_ExtEnd: Integer;
  Bmp: TBitmap;
  PicRect: TRect;
  label NextLoop;
begin
  //POSDLL.dll
  if sPrinter = 0 then
  begin
    POSDLLHandle := LoadLibrary('POSDLL.dll');
    if POSDLLHandle = 0 then
    begin
      ShowMessageBox('动态库POSDLL.dll缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
      Exit;
    end
    else
    begin
      @POS_Open := GetProcAddress(POSDLLHandle, 'POS_Open');
      @POS_Close := GetProcAddress(POSDLLHandle, 'POS_Close');
      @POS_FeedLine := GetProcAddress(POSDLLHandle, 'POS_FeedLine');
      @POS_SetLineSpacing := GetProcAddress(POSDLLHandle, 'POS_SetLineSpacing');
      @POS_CutPaper := GetProcAddress(POSDLLHandle, 'POS_CutPaper');
      @POS_S_TextOut := GetProcAddress(POSDLLHandle, 'POS_S_TextOut');
      @POS_S_SetBarcode := GetProcAddress(POSDLLHandle, 'POS_S_SetBarcode');
      @POS_WriteFile := GetProcAddress(POSDLLHandle, 'POS_WriteFile');
      @POS_Raster_DownloadAndPrintBmpEx := GetProcAddress(POSDLLHandle, 'POS_Raster_DownloadAndPrintBmpEx');
      if (@POS_Open = nil) or (@POS_Close = nil) or
         (@POS_FeedLine = nil) or (@POS_SetLineSpacing = nil) or
         (@POS_CutPaper = nil) or (@POS_S_TextOut = nil) or
         (@POS_S_SetBarcode = nil) or (@POS_WriteFile = nil) or
         (@POS_Raster_DownloadAndPrintBmpEx = nil) then
      begin
        ShowMessageBox('动态库函数缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
        Exit;
      end;
    end;
  end;
  //ZQPortDll.dll
  if sPrinter = 1 then
  begin
    ZQPortDllHandle := LoadLibrary('ZQPortDll.dll');
    if ZQPortDllHandle = 0 then
    begin
      ShowMessageBox('动态库BCEncode.dll缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
      Exit;
    end
    else
    begin
      @IsConnect := GetProcAddress(ZQPortDllHandle, 'IsConnect');
      @SendData := GetProcAddress(ZQPortDllHandle, 'SendData');
      @GetUSBPort := GetProcAddress(ZQPortDllHandle, 'GetUSBPort');
      @ClosePort := GetProcAddress(ZQPortDllHandle, 'ClosePort');
      @PrintQRCode := GetProcAddress(ZQPortDllHandle, 'PrintQRCode');
      @PrintBarcode := GetProcAddress(ZQPortDllHandle, 'PrintBarcode');
      @PrintBmp := GetProcAddress(ZQPortDllHandle, 'PrintBmp');
      if (@IsConnect = nil) or (@SendData = nil) or
         (@GetUSBPort = nil) or (@ClosePort = nil) or
         (@PrintQRCode = nil) or (@PrintBarcode = nil) or
         (@PrintBmp = nil) then
      begin
        ShowMessageBox('动态库函数缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
        Exit;
      end;
    end;
  end;
  //BCEncode.dll / PtImageRW.dll / PtQREncode.dll
  if sPrinter = 2 then
  begin
    //BCEncode.dll
    BCEncodeHandle := LoadLibrary('BCEncode.dll');
    if BCEncodeHandle = 0 then
    begin
      ShowMessageBox('动态库BCEncode.dll缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
      Exit;
    end
    else
    begin
      @MakeBarCode := GetProcAddress(BCEncodeHandle, 'MakeBarCode');
      @MakeBarcodeBmpFile := GetProcAddress(BCEncodeHandle, 'MakeBarcodeBmpFile');
      if (@MakeBarCode = nil) or (@MakeBarcodeBmpFile = nil) then
      begin
        ShowMessageBox('动态库函数缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
        Exit;
      end;
    end;
    //PtImageRW.dll
    PtImageRWHandle := LoadLibrary('PtImageRW.dll');
    if PtImageRWHandle = 0 then
    begin
      ShowMessageBox('动态库PtImageRW.dll缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
      Exit;
    end
    else
    begin
      @PtInitImage := GetProcAddress(PtImageRWHandle, 'PtInitImage');
      @PtSaveImage := GetProcAddress(PtImageRWHandle, 'PtSaveImage');
      @PtFreeImage := GetProcAddress(PtImageRWHandle, 'PtFreeImage');
      if (@PtInitImage = nil) or (@PtSaveImage = nil) or (@PtFreeImage = nil) then
      begin
        ShowMessageBox('动态库函数缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
        Exit;
      end;
    end;
    //PtQREncode.dll
    PtQREncodeHandle := LoadLibrary('PtQREncode.dll');
    if PtQREncodeHandle = 0 then
    begin
      ShowMessageBox('动态库PtQREncode.dll缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
      Exit;
    end
    else
    begin
      @PtQREncodeInit := GetProcAddress(PtQREncodeHandle, 'PtQREncodeInit');
      @PtQREncode := GetProcAddress(PtQREncodeHandle, 'PtQREncode');
      if (@PtQREncodeInit = nil) or (@PtQREncode = nil) then
      begin
        ShowMessageBox('动态库函数缺失或调用失败', '消息', MB_OK + MB_ICONINFORMATION);
        Exit;
      end;
    end;
  end;
  //A7_Command_Manual COM and LPT print 
  IsLPT := False;
  if sPrinter = 3 then
  begin
    if Pos('LPT', Port) > 0 then
    begin
      AssignFile(fp, PChar(Port));
      Rewrite(fp);
      IsLPT := True;
    end;
  end;
  //文件初始化
  AssignFile(f, FileName);
  Reset(f);
  iHandle := 0;
  txtRow := 1;
  txtRowCount := 0;
  Lv_TextHeight := 25;
  sList := TStringList.Create;
  //重打印控制
  Lv_Start := 0;
  Lv_End := 0;
  Lv_ExtStart := 0;
  Lv_ExtEnd := 0;
  while not eof(f) do
  begin
    Readln(f, temp);
    if RePrint <> '' then
    begin
      if temp = '[REPRINTHEAD]' then
        Lv_Start := txtRowCount + 1;
      if temp = '[REPRINTFOOT]' then
        Lv_End := txtRowCount + 1;
      if temp = '[EXCEPTHEAD]' then
        Lv_ExtStart := txtRowCount + 1;
      if temp = '[EXCEPTFOOT]' then
        Lv_ExtEnd := txtRowCount + 1;
    end;
    txtRowCount := txtRowCount + 1;
  end;
  //重打印例外处理
  if (Lv_Start + Lv_End <> 0) and (Lv_ExtStart + Lv_ExtEnd <> 0) then
  begin
    if (Lv_ExtEnd < Lv_Start) or (Lv_ExtStart > Lv_End) then
    begin
      Lv_ExtStart := 0;
      Lv_ExtEnd := 0;
    end
    else
    begin
      if Lv_ExtStart < Lv_Start then
        Lv_ExtStart := Lv_Start;
      if Lv_ExtEnd > Lv_End then
        Lv_ExtEnd := Lv_End;
    end;
  end;
  Reset(f);
  //打印机初始化
  if Lv_Start = 0 then
    prnStart := 1
  else
    prnStart := Lv_Start;
  if Lv_End = 0 then
    prnEnd := txtRowCount
  else
    prnEnd := Lv_End;
  if Lv_Start + Lv_End <> 0 then
    txtRowCount := Lv_End - (Lv_ExtEnd - Lv_ExtStart + 1);
  if sPrinter = 0 then
  begin
    POS_Close();
    if Pos('USB', UpperCase(Port)) > 0 then
    begin
      iHandle := POS_Open('BYUSB-0', 0, 0, 0, 0, $13);
      if iHandle > 0 then
        POS_SetLineSpacing(0);
    end
    else if Pos('LPT', UpperCase(Port)) > 0 then
    begin
      iHandle := POS_Open(PChar(Port), 0, 0, 0, 0, $12);
      if iHandle > 0 then
        POS_SetLineSpacing(0);
    end
    else if Pos('COM', UpperCase(Port)) > 0 then
    begin
      iHandle := POS_Open(PChar(Port), Baud, 5, $00, $00, $01);
      if iHandle > 0 then
        POS_SetLineSpacing(0);
    end;
  end
  else if sPrinter = 1 then
  begin
    if not IsConnect(pChar(Port)) then
      GetUsbPort();
  end
  else if sPrinter = 2 then
  begin
    g_imgheight := 0;
    if Printer.Printing then
      Printer.Abort;
    Printer.Canvas.Font.Name := '宋体';
    Printer.Canvas.Font.Style := [fsBold];
    Printer.Canvas.Font.Size := 8;
    Printer.BeginDoc;
  end
  else if sPrinter = 3 then
  begin
    //Initialize printer     
    //character set
    if IsPrintCom and PrintComm.OpenFlag then
    begin
      PrintComm.PutStr(Char($1B) + Char($40));
      PrintComm.PutStr(Char($1B) + Char($52) + Char($15));
    end
    else if IsLPT then
    begin
      Writeln(fp, Char($1B) + Char($40));
      Writeln(fp, Char($1B) + Char($52) + Char($15));
    end;
  end;
  //打印主逻辑
  while not eof(f) do
  begin
    Readln(f, temp);
    KeyStr := Copy(temp, 1, 12);
    KeyData := Copy(temp, 13, Length(temp) - 12);
    if (txtRow >= prnStart) and (txtRow <= prnEnd) then
    begin
      if (Lv_ExtStart + Lv_ExtEnd <> 0) and (RePrint <> '') then
      begin
        if (txtRow >= Lv_ExtStart) and (txtRow <= Lv_ExtEnd) then
          goto NextLoop;
      end;
      if KeyStr = '[INTIME0001]' then
      begin
        if Length(gImageList) >= StrToInt(KeyData) + 1 then
        begin
          ImgStr := gImageList[StrToInt(KeyData)];
          if sPrinter = 0 then
          begin
            if FileExists(ImgStr) then
            begin
              if P_PrintType = 'TM88' then
                POS_WriteFile(iHandle, PChar(Char($1C) + Char($70) + Char(StrToInt(KeyData) + 1) + Char(0)), 4)
              else
                POS_Raster_DownloadAndPrintBmpEx(pChar(ImgStr), 0, 1, 1, 104);
            end;
          end
          else if sPrinter = 1 then
          begin
            if FileExists(ImgStr) then
              PrintBmp(pChar(Port), pChar(ImgStr), 0);
          end
          else if sPrinter = 2 then
          begin
            if FileExists(ImgStr) then
            begin
              Bmp := TBitmap.Create;
              Bmp.LoadFromFile(ImgStr);
              Printer.Canvas.Draw(0, g_imgheight, Bmp);
              g_imgheight := g_imgheight + Bmp.Height;
              Bmp.Free;
            end;
          end
          else if sPrinter = 3 then
          begin
            if FileExists(ImgStr) then
            begin
              if IsPrintCom and PrintComm.OpenFlag then
              begin
                PrintComm.PutStr(Char($1C) + Char($71) + Char($01) + BitMapToNVPrinterData(ImgStr));
                PrintComm.PutStr(Char($1C) + Char($70) + Char($01) + Char($00));
              end
              else if IsLPT then
              begin
                Writeln(fp, Char($1C) + Char($71) + Char($01) + BitMapToNVPrinterData(ImgStr));
                Writeln(fp, Char($1C) + Char($70) + Char($01) + Char($00));
              end;
            end;
          end;
        end;
      end
      else if KeyStr = '[INTIME0002]' then
      begin
        if Length(gImageList) >= StrToInt(KeyData) + 1 then
        begin
          ImgStr := gImageList[StrToInt(KeyData)];
          if sPrinter = 0 then
          begin
            if FileExists(ImgStr) then
            begin
              if P_PrintType = 'TM88' then
                POS_WriteFile(iHandle, PChar(Char($1C) + Char($70) + Char(StrToInt(KeyData) + 1) + Char(0)), 4)
              else
              begin
                POS_Raster_DownloadAndPrintBmpEx(pChar(ImgStr), 0, 2, 2, 52);
                POS_WriteFile(iHandle, Pchar(Char($1b) + Char($40)), 2);
              end;
            end;
          end
          else if sPrinter = 1 then
          begin
            if FileExists(ImgStr) then
              PrintBmp(pChar(Port), pChar(ImgStr), 3);
          end
          else if sPrinter = 2 then
          begin
            if FileExists(ImgStr) then
            begin
              Bmp := TBitmap.Create;
              Bmp.LoadFromFile(ImgStr);
              PicRect := Rect(0, g_imgheight, Bmp.width * 2, g_imgheight + Bmp.height * 2);
              Printer.Canvas.StretchDraw(PicRect, Bmp);
              g_imgheight := g_imgheight + Bmp.Height * 2;
              Bmp.Free;
            end;
          end
          else if sPrinter = 3 then
          begin
            if FileExists(ImgStr) then
            begin
              if IsPrintCom and PrintComm.OpenFlag then
              begin
                PrintComm.PutStr(Char($1C) + Char($71) + Char($01) + BitMapToNVPrinterData(ImgStr));
                PrintComm.PutStr(Char($1C) + Char($70) + Char($01) + Char($03));
              end
              else if IsLPT then
              begin
                Writeln(fp, Char($1C) + Char($71) + Char($01) + BitMapToNVPrinterData(ImgStr));
                Writeln(fp, Char($1C) + Char($70) + Char($01) + Char($03));
              end;
            end;
          end;
        end;
      end
      else if KeyStr = '[INTIME1001]' then
      begin
        if sPrinter = 0 then
          POS_S_TextOut(PChar(KeyData + Char(13) + Char(10)), 0, 2, 2, POS_FONT_TYPE_STANDARD, POS_FONT_STYLE_NORMAL)
        else if sPrinter = 1 then
        begin
          sList.Add(char($1d) + char($21) + char($11) + KeyData + char($1d) + char($21) + char($00));
          Lv_Length := Length(sList.Text);
          SendData(pChar(Port), pChar(sList.Text), Lv_Length);
          sList.Clear;
        end
        else if sPrinter = 2 then
        begin
          Printer.Canvas.Font.Size := 16;
          Printer.Canvas.TextOut(0, g_imgheight, KeyData);
          g_imgheight := g_imgheight + Lv_TextHeight * 2;
          Printer.Canvas.Font.Size := 8;
        end
        else if sPrinter = 3 then
        begin
          if IsPrintCom and PrintComm.OpenFlag then
          begin
            PrintComm.PutStr(Char($1D) + Char($21) + Char($11));       //width + height hex put in third param
            PrintComm.PutStr(KeyData);
            PrintComm.PutStr(Char($1D) + Char($21) + Char($00));
          end
          else if IsLPT then
          begin
            Writeln(fp, Char($1D) + Char($21) + Char($11));
            Writeln(fp, KeyData);
            Writeln(fp, Char($1D) + Char($21) + Char($00));
          end;
        end;
      end
      else if KeyStr = '[INTIME9800]' then
      begin
        if RePrint <> '' then
        begin
          if sPrinter = 0 then
            POS_S_TextOut(PChar(RePrint + Char(13) + Char(10)), 0, 1, 1, POS_FONT_TYPE_STANDARD, POS_FONT_STYLE_NORMAL)
          else if sPrinter = 1 then
            sList.Add(RePrint)
          else if sPrinter = 2 then
          begin
            Printer.Canvas.TextOut(0, g_imgheight, RePrint);
            g_imgheight := g_imgheight + Lv_TextHeight;
          end
          else if sPrinter = 3 then
          begin
            if IsPrintCom and PrintComm.OpenFlag then
              PrintComm.PutStr(RePrint)
            else if IsLPT then
              Writeln(fp, RePrint);
          end;
        end;
      end
      else if KeyStr = '[INTIME9801]' then
      begin
        if sPrinter = 0 then
        begin
          POS_S_SetBarcode(PChar(KeyData), 0, POS_BARCODE_TYPE_JAN13, 2, 50, POS_FONT_TYPE_COMPRESSED, POS_HRI_POSITION_NONE, Length(KeyData));
          POS_S_TextOut(PChar(' ' + Char(13) + Char(10)), 0, 1, 1, POS_FONT_TYPE_STANDARD, POS_FONT_STYLE_NORMAL)
        end
        else if sPrinter = 1 then
        begin
          Lv_Length := Length(KeyData);
          PrintBarcode(pChar(Port), pChar(KeyData), Lv_Length, 104, 60, 3, 0, 48);
          sList.Add(' ');
          Lv_Length := Length(sList.Text);
          SendData(pChar(Port), pChar(sList.Text), Lv_Length);
          sList.Clear;
        end
        else if sPrinter = 2 then
        begin
          if KeyData <> '' then
          begin
            Bmp := TBitmap.Create;
            Bmp.Handle := MakeBarCode(2, KeyData, 2, 4, 60, 0, 0, 0);
            Printer.Canvas.Draw(0, g_imgheight, Bmp);
            g_imgheight := g_imgheight + Bmp.Height;
            Printer.Canvas.TextOut(0, g_imgheight, ' ');
            g_imgheight := g_imgheight + Lv_TextHeight;
            Bmp.Free;
          end;
        end
        else if sPrinter = 3 then
        begin
          if IsPrintCom and PrintComm.OpenFlag then
          begin
            PrintComm.PutStr(Char($1D) + Char($6B) + Char(67) + Char(Length(KeyData)) + KeyData);
            PrintComm.PutStr(' ');
          end
          else if IsLPT then
          begin
            Writeln(fp, Char($1D) + Char($6B) + Char(67) + Char(Length(KeyData)) + KeyData);
            Writeln(fp, ' ');
          end;
        end;
      end
      else if KeyStr = '[INTIME9802]' then
      begin
        if sPrinter = 0 then
        begin
          KeyData := '{A' + LeftStr(KeyData, Length(KeyData) - 14) + '{C' + DecToStr(RightStr(KeyData, 14));
          POS_S_SetBarcode(PChar(KeyData), 0, POS_BARCODE_TYPE_CODE128, 2, 50, POS_FONT_TYPE_COMPRESSED, POS_HRI_POSITION_BELOW, Length(KeyData));
        end
        else if sPrinter = 1 then
        begin
          Lv_Length := Length(KeyData);
          PrintBarcode(pChar(Port), pChar(KeyData), Lv_Length, 111, 60, 3, 0, 50);
          sList.Add(' ');
          Lv_Length := Length(sList.Text);
          SendData(pChar(Port), pChar(sList.Text), Lv_Length);
          sList.Clear;
        end
        else if sPrinter = 2 then
        begin
          if KeyData <> '' then
          begin
            Bmp := TBitmap.Create;
            Bmp.Handle := MakeBarCode(3, KeyData, 2, 4, 70, 0, 3, 0);
            Printer.Canvas.Draw(0, g_imgheight, Bmp);
            g_imgheight := g_imgheight + Bmp.Height;
            Bmp.Free;
          end;
        end
        else if sPrinter = 3 then
        begin
          if IsPrintCom and PrintComm.OpenFlag then
          begin
            PrintComm.PutStr(Char($1D) + Char($6B) + Char(73) + Char(Length(KeyData)) + KeyData);
            PrintComm.PutStr(' ');
          end
          else if IsLPT then
          begin
            Writeln(fp, Char($1D) + Char($6B) + Char(73) + Char(Length(KeyData)) + KeyData);
            Writeln(fp, ' ');
          end;
        end;
      end
      else if KeyStr = '[INTIME9811]' then
      begin
        if sPrinter = 0 then
          POS_WriteFile(iHandle, Pchar(Char($1d) + Char($6b) + Char($0b) + Char($51) + Char($41) + Char($2c) + KeyData + Char($00)), Length(KeyData) + 7)
        else if sPrinter = 1 then
        begin
          sList.Add(KeyData);
          Lv_Length := Length(sList.Text);
          PrintQRCode(pChar(Port), 50, pChar(sList.Text), Lv_Length);
          sList.Clear;
          sList.Add(' ');
          sList.Add(' ');
          Lv_Length := Length(sList.Text);
          SendData(pChar(Port), pChar(sList.Text), Lv_Length);
          sList.Clear;
        end
        else if sPrinter = 2 then
        begin
          CreateQRCode(KeyData, PT_QR_VERSION_AUTO, PT_QR_ECCLEVEL_L, Floor(Length(KeyData) / 250) + 4);
          if FileExists(g_path + 'QRCode.bmp') then
          begin
            Bmp := TBitmap.Create;
            Bmp.LoadFromFile(g_path + 'QRCode.bmp');
            Printer.Canvas.Draw(0, g_imgheight, Bmp);
            g_imgheight := g_imgheight + Bmp.Height;
            Bmp.Free;
          end;
        end
        else if sPrinter = 3 then
        begin
          CreateQRCode(KeyData, PT_QR_VERSION_AUTO, PT_QR_ECCLEVEL_L, Floor(Length(KeyData) / 250) + 4);
          if FileExists(g_path + 'QRCode.bmp') then
          begin
            if IsPrintCom and PrintComm.OpenFlag then
            begin
              PrintComm.PutStr(Char($1C) + Char($71) + Char($01) + BitMapToNVPrinterData(g_path + 'QRCode.bmp'));
              PrintComm.PutStr(Char($1C) + Char($70) + Char($01) + Char($03));
            end
            else if IsLPT then
            begin
              Writeln(fp, Char($1C) + Char($71) + Char($01) + BitMapToNVPrinterData(g_path + 'QRCode.bmp'));
              Writeln(fp, Char($1C) + Char($70) + Char($01) + Char($03));
            end;
          end;
        end;
      end
      else if (KeyStr = '[INTIME9901]') or ((RePrint <> '') and (temp = '[REPRINTFOOT]')) then
      begin
        if sPrinter = 0 then
        begin
          for i := 1 to 4 do POS_FeedLine();
          POS_CutPaper(POS_CUT_MODE_PARTIAL_EX, 0);
        end
        else if sPrinter = 1 then
        begin
          sList.Add(' ');
          sList.Add(' ');
          sList.Add(' ');
          sList.Add(' ');
          sList.Add(' ');
          SpecStr := #$1B#$6D;
          sList.Add(SpecStr);
          Lv_Length := length(sList.Text);
          SendData(pChar(Port), pChar(sList.Text), Lv_Length);
          sList.Clear;
        end
        else if sPrinter = 2 then
        begin
          Printer.Canvas.TextOut(0, g_imgheight, '.                                        .');
          g_imgheight := g_imgheight + Lv_TextHeight;
          Printer.EndDoc;
          if txtRow <> txtRowCount then
          begin
            g_imgheight := 0;
            Printer.BeginDoc;
          end;
        end
        else if sPrinter = 3 then
        begin
          if IsPrintCom and PrintComm.OpenFlag then
          begin
            for i := 1 to 4 do PrintComm.PutStr(Char($0A));
            PrintComm.PutStr(Char($1B) + Char($69));
          end
          else if IsLPT then
          begin
            for i := 1 to 4 do PrintComm.PutStr(Char($0A));
            Writeln(fp, Char($1B) + Char($69));
          end;
        end;
      end
      else if (KeyStr = '[INTIME9902]') or ((RePrint <> '') and (temp = '[REPRINTFOOT]')) then
      begin
        if sPrinter = 0 then
        begin
          for i := 1 to 4 do POS_FeedLine();
          POS_CutPaper(POS_CUT_MODE_FULL, 0);
        end
        else if sPrinter = 1 then
        begin
          sList.Add(' ');
          sList.Add(' ');
          sList.Add(' ');
          sList.Add(' ');
          sList.Add(' ');
          SpecStr := #$1B#$6D;
          sList.Add(SpecStr);
          Lv_Length := length(sList.Text);
          SendData(pChar(Port), pChar(sList.Text), Lv_Length);
          sList.Clear;
        end
        else if sPrinter = 2 then
        begin
          Printer.Canvas.TextOut(0, g_imgheight, '.                                        .');
          g_imgheight := g_imgheight + Lv_TextHeight;
          Printer.EndDoc;
          if txtRow <> txtRowCount then
          begin
            g_imgheight := 0;
            Printer.BeginDoc;
          end;
        end
        else if sPrinter = 3 then
        begin
          if IsPrintCom and PrintComm.OpenFlag then
          begin
            for i := 1 to 4 do PrintComm.PutStr(Char($0A));
            PrintComm.PutStr(Char($1D) + Char($56) + Char($00));
          end
          else if IsLPT then
          begin
            for i := 1 to 4 do PrintComm.PutStr(Char($0A));
            Writeln(fp, Char($1D) + Char($56) + Char($00));
          end;
        end;
      end
      else if (temp = '[REPRINTHEAD]') or (temp = '[EXCEPTHEAD]') or (temp = '[EXCEPTFOOT]') or ((RePrint = '') and (temp = '[REPRINTFOOT]')) then
      begin
        //什么都不做
      end
      else
      begin
        if sPrinter = 0 then
          POS_S_TextOut(PChar(temp + Char(13) + Char(10)), 0, 1, 1, POS_FONT_TYPE_STANDARD, POS_FONT_STYLE_NORMAL)
        else if sPrinter = 1 then
        begin
          sList.Add(temp);
          Lv_Length := Length(sList.Text);
          SendData(pChar(Port), pChar(sList.Text), Lv_Length);
          sList.Clear;
        end
        else if sPrinter = 2 then
        begin
          Printer.Canvas.TextOut(0, g_imgheight, temp);
          g_imgheight := g_imgheight + Lv_TextHeight;
        end
        else if sPrinter = 3 then
        begin
          if IsPrintCom and PrintComm.OpenFlag then
            PrintComm.PutStr(temp)
          else if IsLPT then
            Writeln(fp, temp);
        end;
      end;
      NextLoop:
    end;
    txtRow := txtRow + 1;
  end;
  //释放打印对象
  sList.Free;
  CloseFile(f);
  if sPrinter = 0 then
  begin
    POS_Close();
    FreeLibrary(POSDLLHandle);
  end
  else if sPrinter = 1 then
  begin
    ClosePort(pChar(Port));
    FreeLibrary(ZQPortDllHandle);
  end
  else if sPrinter = 2 then
  begin
    if Printer.Printing then
      Printer.Abort;
    FreeLibrary(BCEncodeHandle);
    FreeLibrary(PtImageRWHandle);
    FreeLibrary(PtQREncodeHandle);
  end
  else if sPrinter = 3 then
  begin
    if IsLPT then
    begin
      Flush(fp);
      CloseFile(fp);
    end;
  end;
end;

end.
