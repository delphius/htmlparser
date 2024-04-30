unit HTML2TextRenderer;

{$mode objfpc}{$H+}
interface

uses
  Classes,
  SysUtils;

{$include entities.inc}

type
  TToken = record
    Name: String;
    StartPos: Integer;
    EndPos: Integer;
    PairIndex: Integer;
  end;

var Tags: array of TToken;

type
  THTML2TextRenderer = class
  private
    FText: string;
    FIgnoreTags: TStringList;
    FSpecialTags: TStringList;
    FLineEnding: string;

    function IsTagIgnored(const TagName: string): Boolean;
    function IsSpecialTag(const TagName: string): Boolean;
    function ExtractTagName(const Tag: string): string;
    function StripTags(const Text: string): string;
    function IsWhitespace(const Text: string): Boolean;
    procedure AppendText(const Text: string);
    function DecodeHTMLEntities(const Text: string): string;
    procedure RemoveEmptyLines;
  public
    constructor Create;
    destructor Destroy; override;
    function RenderHTML(HTML: string): string;
  end;

implementation

constructor THTML2TextRenderer.Create;
begin
  FIgnoreTags := TStringList.Create;
  FSpecialTags := TStringList.Create;

  // Здесь можно добавить игнорируемые теги
  FIgnoreTags.Add('script');
  FIgnoreTags.Add('style');

  // Здесь можно добавить специальные теги
  FSpecialTags.Add('b');
  FSpecialTags.Add('i');
  FSpecialTags.Add('u');
  FSpecialTags.Add('strong');
  FSpecialTags.Add('em');

  // Установка LineEnding в зависимости от операционной системы
  {$IFDEF MSWINDOWS}
    FLineEnding := #13#10;
  {$ELSE}
    FLineEnding := #10;
  {$ENDIF}
end;

destructor THTML2TextRenderer.Destroy;
begin
  FIgnoreTags.Free;
  FSpecialTags.Free;
  inherited;
end;

function THTML2TextRenderer.RenderHTML(HTML: string): string;
var
  TagStartPos, TagEndPos, index: Integer;
  Tag, TagName: string;
  inScript, inHead: Boolean;
  Token: TToken;
  OpenIndex, OpenCount, CloseIndex, StartChar, CharCount: Integer;
begin
  FText := '';
  index := 0;
  inScript := False;
  inHead := False;
  TagStartPos := Integer(Pos('<', HTML));

  while TagStartPos > 0 do
  begin
    TagEndPos := Integer(Pos('>', HTML, TagStartPos + 1));

    if TagEndPos = 0 then Break;

    Tag := Copy(HTML, TagStartPos, TagEndPos - TagStartPos + 1);

    TagName := ExtractTagName(Tag);

    case TagName of
    '/script': inScript := False;
    '/head': inHead := False;
    end;

    if (not inScript) and (not inHead) then
      begin
        inc(index);
        With Token do
          begin
            Name := TagName;
            StartPos := TagStartPos;
            EndPos := TagEndPos;
            PairIndex := -1; // помечаем все безпарными
          end;
        SetLength(Tags, Length(Tags) + 1);
        Tags[Length(Tags) - 1] := Token;
        //writeln(IntToStr(index) + '. ' + ' ' + TagName + ' ' + IntToStr(TagStartPos) + ' ' + IntToStr(TagEndPos));
      end;
    
    case TagName of
    'script': inScript := True;
    'head': inHead := True;
    end;

    if not inScript then
      TagStartPos := Integer(Pos('<', HTML, TagEndPos + 1))
      else
      TagStartPos := Integer(Pos('</script', HTML, TagEndPos + 1));
  end;
  //writeln('Open: ' + IntToStr(Length(OpeningTags)) + ', Closing: ' + IntToStr(Length(ClosingTags)));

// Находим пары открывающих и закрывающих тегов, безпарные так и остаются PairIndex = -1
  for OpenIndex := 0 to Integer(High(Tags) - 1) do
  begin
   OpenCount := 1;
   if Tags[OpenIndex].Name[1] <> '/'
    then
     begin
      for CloseIndex := Integer(OpenIndex + 1) to Integer(High(Tags)) do
      begin
        if Tags[CloseIndex].Name = Tags[OpenIndex].Name then
        begin
          Inc(OpenCount);
        end
        else if Tags[CloseIndex].Name = '/' + Tags[OpenIndex].Name then
        begin
          Dec(OpenCount);
          if OpenCount = 0 then
          begin
            Tags[CloseIndex].PairIndex := OpenIndex;
            Tags[OpenIndex].PairIndex := CloseIndex;
            Break;
          end;
        end;
      end;
     end;
  end;

  // Выводим информацию о Tags
  {for index := 0 to Integer(High(Tags)) do
  begin
    writeln('TagIndex ' + IntToStr(index) + ': ' + Tags[index].Name + ' Open: ' +
      IntToStr(Tags[index].StartPos) + '-' + IntToStr(Tags[index].EndPos) +
      ' PairIndex: ' + IntToStr(Tags[index].PairIndex));
  end;}

  for index := 0 to Integer(High(Tags) - 1) do
  begin
        if Tags[index].Name <> 'script'
            then
              begin
                StartChar := Integer(Tags[index].EndPos + 1);
                CharCount := Integer(Tags[index + 1].StartPos - Tags[index].EndPos - 1);
                if (CharCount > 0) // и между ним и следующим тегом что-то есть
                then
                  begin
                    AppendText(copy(HTML, StartChar, CharCount));
                    //writeln(Tags[index].Name);
                    //WriteLn('Is between: ' + IntToStr(StartChar) + ' and ' + IntToStr(StartChar + CharCount) + ', amount: ' + IntToStr(CharCount) + ' symbols');
                    //writeln('');
                  end;
                end;
  end;

  // Удаление пустых строк
  RemoveEmptyLines;

  // Декодируем HTML-сущности
  Result := DecodeHTMLEntities(FText);
end;

function THTML2TextRenderer.IsTagIgnored(const TagName: string): Boolean;
begin
  Result := FIgnoreTags.IndexOf(ExtractTagName(TagName)) <> -1;
end;

function THTML2TextRenderer.IsSpecialTag(const TagName: string): Boolean;
begin
  Result := FSpecialTags.IndexOf(ExtractTagName(TagName)) <> -1;
end;

function THTML2TextRenderer.ExtractTagName(const Tag: string): string;
var
  TagNameEndPos: Integer;
begin
  TagNameEndPos := Integer(Pos(' ', Tag));

  if TagNameEndPos = 0 then
    TagNameEndPos := Integer(Pos('>', Tag));

  if TagNameEndPos > 0 then
    Result := Copy(Tag, 2, TagNameEndPos - 2)
  else
    Result := '';
end;

function THTML2TextRenderer.StripTags(const Text: string): string;
var
  TagStartPos, TagEndPos: Integer;
  Tag, StrippedText: string;
begin
  StrippedText := Text;
  TagStartPos := Integer(Pos('<', StrippedText));

  while TagStartPos > 0 do
  begin
    TagEndPos := Integer(Pos('>', StrippedText, TagStartPos + 1));

    if TagEndPos = 0 then
      Break;

    Tag := Copy(StrippedText, TagStartPos, TagEndPos - TagStartPos + 1);
    StrippedText := StringReplace(StrippedText, Tag, '', []);

    TagStartPos := Integer(Pos('<', StrippedText));
  end;

  Result := StrippedText;
end;

function THTML2TextRenderer.IsWhitespace(const Text: string): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 1 to Integer(Length(Text)) do
  begin
    if not (Text[I] in [#9, #10, #13, #32]) then
    begin
      Result := False;
      Break;
    end;
  end;
end;

procedure THTML2TextRenderer.AppendText(const Text: string);
begin
  if not IsWhitespace(Text) then
  begin
    if FText <> '' then
      FText += FLineEnding;
    FText += Text;
  end;
end;

function THTML2TextRenderer.DecodeHTMLEntities(const Text: string): string;
var
  MatchPos, SemicolonPos: Integer;
  EntityCode, EntityName: string;
  Dec, I: Integer;
  FoundEntity: Boolean;
begin
  Result := Text;
  MatchPos := Pos('&', Result);
  while MatchPos > 0 do
  begin
    SemicolonPos := Pos(';', Result, MatchPos);
    if SemicolonPos > 0 then
    begin
      EntityCode := Copy(Result, MatchPos + 1, SemicolonPos - MatchPos - 1);
      WriteLn(EntityCode);
      // Проверяем, является ли сущность числовым кодом
      if EntityCode[1] = '#' then
      begin
        EntityName := Copy(EntityCode, 2, Length(EntityCode));
        Dec := StrToIntDef(EntityName, 0);
        Result := StringReplace(Result, '&' + EntityCode + ';', UTF8Encode(WideChar(Dec)), []);
      end
      else
      begin
        FoundEntity := False;
        for I := Low(NamedEntities) to High(NamedEntities) do
        begin
          if NamedEntities[I].Name = ('&' + EntityCode + ';') then
          begin
            //WriteLn(EntityCode + ' ' + UTF8Encode(NamedEntities[I].Value));
            Result := StringReplace(Result, ('&' + EntityCode + ';'), NamedEntities[I].Value, []);
            FoundEntity := True;
            Break;
          end;
        end;
      end;
      
      MatchPos := Pos('&', Result, SemicolonPos + 1);
    end
    else
    begin
      // Некорректный формат HTML-сущности
      Break;
    end;
  end;
end;


procedure THTML2TextRenderer.RemoveEmptyLines;
var
  Lines: TStringList;
  I: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := FText;
    for I := Integer(Lines.Count - 1) downto 0 do
    begin
      if IsWhitespace(Lines[I]) then
        Lines.Delete(I);
    end;
    FText := Lines.Text;
  finally
    Lines.Free;
  end;
end;


end.