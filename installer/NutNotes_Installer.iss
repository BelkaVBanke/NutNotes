; =====================================================================
; NutNotes REAPER Plugin Installer & Updater
; Built with Inno Setup 6
; =====================================================================

#define MyAppName "NutNotes"
#define MyAppVersion "0.5.1-beta"
#define MyAppPublisher "BelkaVBanke"
#define MyAppURL "https://github.com/BelkaVBanke/NutNotes"
#define MyAppReleasesURL "https://github.com/BelkaVBanke/NutNotes/releases"
#define MyAppApiURL "https://api.github.com/repos/BelkaVBanke/NutNotes/releases/latest"

[Setup]
AppId={{C8E64931-729B-4B76-92F6-B91F8F617150}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppReleasesURL}

; Install to user's REAPER resource directory (no admin rights needed)
DefaultDirName={userappdata}\REAPER
AppendDefaultDirName=no
DirExistsWarning=no
EnableDirDoesntExistWarning=no
PrivilegesRequired=lowest
OutputBaseFilename=NutNotes_Setup_v{#MyAppVersion}
OutputDir=..\build\v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
SetupIconFile=assets\app_icon.ico
WizardStyle=modern
WizardImageFile=assets\wizard_large.bmp
WizardSmallImageFile=assets\wizard_small.bmp
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Scripts\NutNotes\assets\acorn_colored.png
UninstallDisplayName={#MyAppName} (REAPER Subtitle & Dubbing Assistant)

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
russian.WelcomeLabel1=Установка и обновление NutNotes
russian.WelcomeLabel2=Добро пожаловать в установщик NutNotes для Cockos REAPER.%n%nNutNotes — инструмент для дубляжа и закадрового озвучания, а именно Plugin для отображения субтитров ASS и SRT.%n%nПеред началом убедитесь, что Cockos REAPER закрыт.
russian.SelectDirLabel3=Укажите каталог ресурсов Cockos REAPER:
russian.SelectDirBrowseLabel=Для продолжения нажмите «Далее». Если вы используете портативную версию REAPER, укажите ее папку.

english.WelcomeLabel1=NutNotes Setup and Updater
english.WelcomeLabel2=Welcome to the NutNotes installer for Cockos REAPER.%n%nNutNotes is a subtitle and dubbing assistant for ASS and SRT subtitles.%n%nPlease close Cockos REAPER before continuing.

[CustomMessages]
russian.WarnOldVersion=Внимание! Во время установки предыдущая версия плагина NutNotes и её экшены в REAPER будут удалены и обновлены.%n%nФайлы ваших настроек (reaper-extstate.ini) и данные проектов сохранены и затронуты НЕ будут.%n%nПродолжить установку?
russian.StatusCleaning=Удаление предыдущей версии плагина и очистка старых экшенов...
russian.VersionPageCaption=Выбор версии NutNotes
russian.VersionPageSubCaption=Выберите версию плагина для установки.
russian.VersionPageDesc=Выберите источник для установки плагина NutNotes:
russian.VersionBundled=Вшитая версия (v{#MyAppVersion}) — автономная установка (рекомендуется)
russian.VersionGithub=Последняя версия с GitHub
russian.GitChecking=Проверка доступности релизов на GitHub...
russian.GitLatestFound=Доступна последняя версия: %1
russian.GitConnectionFailed=Не удалось подключиться к GitHub (нет сети или репозиторий недоступен).
russian.GitRetryBtn=Повторить попытку
russian.StatusDownloading=Загрузка обновления NutNotes с GitHub...
russian.ReaperRunningWarn=Внимание! Cockos REAPER в данный момент запущен.%n%nПожалуйста, закройте REAPER перед установкой или обновлением NutNotes, чтобы избежать блокировки системных файлов плагина.%n%nПосле закрытия REAPER нажмите «Повторить» для продолжения или «Отмена» для выхода.

english.WarnOldVersion=Warning! During installation, the previous version of NutNotes and its actions in REAPER will be removed and updated.%n%nYour settings (reaper-extstate.ini) and project files will NOT be affected.%n%nContinue with installation?
english.StatusCleaning=Removing previous plugin files and cleaning old actions...
english.VersionPageCaption=NutNotes Version Selection
english.VersionPageSubCaption=Choose the version of the plugin to install.
english.VersionPageDesc=Select the source for installing NutNotes:
english.VersionBundled=Bundled version (v{#MyAppVersion}) — offline install (recommended)
english.VersionGithub=Latest release from GitHub
english.GitChecking=Checking for releases on GitHub...
english.GitLatestFound=Latest version available: %1
english.GitConnectionFailed=Unable to connect to GitHub (offline or repository unavailable).
english.GitRetryBtn=Retry
english.StatusDownloading=Downloading NutNotes update from GitHub...
english.ReaperRunningWarn=Warning! Cockos REAPER is currently running.%n%nPlease close REAPER before installing or updating NutNotes to prevent plugin file locking.%n%nAfter closing REAPER, click "Retry" to continue or "Cancel" to exit.

[Tasks]
Name: "dependencies"; Description: "Установить зависимости в REAPER (ReaImGui x64, ReaPack x64, js_ReaScriptAPI x64, ReaTeam Extensions API)"; GroupDescription: "Зависимости:"; Flags: checkablealone
Name: "autostart"; Description: "Включить автозапуск NutNotes при старте REAPER (Scripts/__startup.lua)"; GroupDescription: "Интеграция в REAPER:"; Flags: unchecked
Name: "toolbar"; Description: "Добавить кнопку запуска NutNotes на главную панель (Main Toolbar)"; GroupDescription: "Интеграция в REAPER:"; Flags: unchecked
Name: "examples"; Description: "Установить примеры и тестовые файлы субтитров"; GroupDescription: "Дополнительно:"; Flags: unchecked

[Files]
; 1. Core script files
Source: "..\NutNotes.lua"; DestDir: "{app}\Scripts\NutNotes"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}\Scripts\NutNotes"; Flags: ignoreversion
Source: "..\modules\*"; DestDir: "{app}\Scripts\NutNotes\modules"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\assets\*"; DestDir: "{app}\Scripts\NutNotes\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

; 2. Examples (optional task)
Source: "..\test_samples\*"; DestDir: "{app}\Scripts\NutNotes\test_samples"; Tasks: examples; Flags: ignoreversion recursesubdirs createallsubdirs

; 3. Dependencies (optional task)
Source: "dependencies\reaper_imgui-x64.dll"; DestDir: "{app}\UserPlugins"; Tasks: dependencies; Flags: ignoreversion
Source: "dependencies\reaper_reapack-x64.dll"; DestDir: "{app}\UserPlugins"; Tasks: dependencies; Flags: ignoreversion
Source: "dependencies\reaper_js_ReaScriptAPI64.dll"; DestDir: "{app}\UserPlugins"; Tasks: dependencies; Flags: ignoreversion
Source: "dependencies\ReaTeam Extensions\*"; DestDir: "{app}\Scripts\ReaTeam Extensions"; Tasks: dependencies; Flags: ignoreversion recursesubdirs createallsubdirs

; 4. Toolbar icon (always copy or if toolbar task)
Source: "assets\nutnotes_toolbar.png"; DestDir: "{app}\Data\toolbar_icons"; Flags: ignoreversion
Source: "assets\nutnotes_icon_30.png"; DestDir: "{app}\Data\toolbar_icons"; Flags: ignoreversion

[Code]
var
  OnlineVersionFound: Boolean;
  RemoteVersionTag: String;
  RemoteDownloadUrl: String;
  UseOnlineDownload: Boolean;
  DownloadedZipPath: String;
  ExtractedTempDir: String;

  VersionPage: TWizardPage;
  RbBundled: TRadioButton;
  RbGitHub: TRadioButton;
  LblGitStatus: TLabel;
  BtnGitRetry: TButton;
  GitCheckPerformed: Boolean;
  GitCheckFinished: Boolean;
  DirPrepopulated: Boolean;
  DownloadPage: TDownloadWizardPage;
  GitResultFile: String;
  GitWorkerScript: String;
  OldVersionWarningConfirmed: Boolean;
  LastWarnedPath: String;

function InitializeSetup(): Boolean;
var
  Wnd: HWND;
begin
  Result := True;
  while True do
  begin
    Wnd := FindWindowByClassName('REAPERwnd');
    if Wnd = 0 then
      Break;

    if MsgBox(CustomMessage('ReaperRunningWarn'), mbError, MB_RETRYCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

// ---------- Keep your existing CleanVersionStr and
// CompareSemanticVersions functions unchanged. ----------

function CleanVersionStr(Version: String): String;
var
  HyphenPos: Integer;
begin
  Version := Trim(Version);

  if (Length(Version) > 0) and
     ((Version[1] = 'v') or (Version[1] = 'V')) then
    Delete(Version, 1, 1);

  // Strip pre-release suffix (e.g. -beta, -rc) for numeric comparison
  HyphenPos := Pos('-', Version);
  if HyphenPos > 0 then
    Version := Copy(Version, 1, HyphenPos - 1);

  Result := Version;
end;

function CompareSemanticVersions(VersionA, VersionB: String): Integer;
var
  A, B: String;
  PartA, PartB: String;
  DotA, DotB: Integer;
  NumA, NumB: Integer;
begin
  A := CleanVersionStr(VersionA);
  B := CleanVersionStr(VersionB);

  while (A <> '') or (B <> '') do
  begin
    DotA := Pos('.', A);
    DotB := Pos('.', B);

    if DotA > 0 then
    begin
      PartA := Copy(A, 1, DotA - 1);
      Delete(A, 1, DotA);
    end
    else
    begin
      PartA := A;
      A := '';
    end;

    if DotB > 0 then
    begin
      PartB := Copy(B, 1, DotB - 1);
      Delete(B, 1, DotB);
    end
    else
    begin
      PartB := B;
      B := '';
    end;

    NumA := StrToIntDef(PartA, 0);
    NumB := StrToIntDef(PartB, 0);

    if NumA > NumB then
    begin
      Result := 1;
      Exit;
    end;

    if NumA < NumB then
    begin
      Result := -1;
      Exit;
    end;
  end;

  Result := 0;
end;
procedure FinishGitHubReleaseCheck(Success: Boolean); forward;

procedure StartGitHubReleaseCheck();
var
  PowerShellCode: String;
  ResultCode: Integer;
begin
  GitCheckFinished := False;
  WizardForm.NextButton.Enabled := False;
  WizardForm.Refresh();

  OnlineVersionFound := False;
  RemoteVersionTag := '';
  RemoteDownloadUrl := '';

  // Always select the bundled version first. The user can continue offline.
  RbBundled.Checked := True;
  RbGitHub.Enabled := False;
  RbGitHub.Caption := CustomMessage('VersionGithub') + ' (проверка...)';
  LblGitStatus.Font.Color := clWindowText;
  LblGitStatus.Caption := CustomMessage('GitChecking');
  BtnGitRetry.Visible := False;

  GitResultFile := ExpandConstant('{tmp}\nutnotes_github_result.txt');
  GitWorkerScript := ExpandConstant('{tmp}\nutnotes_github_check.ps1');
  DeleteFile(GitResultFile);

  // Network I/O runs in a separate PowerShell process, not in the installer UI.
  PowerShellCode :=
    '$ErrorActionPreference = "Stop"' + #13#10 +
    'try {' + #13#10 +
    '  $r = Invoke-RestMethod -Uri "{#MyAppApiURL}" -Headers @{"User-Agent"="NutNotes-Installer"} -TimeoutSec 10' + #13#10 +
    '  $tag = [string]$r.tag_name' + #13#10 +
    '  $url = ""' + #13#10 +
    '  foreach ($a in $r.assets) { if ($a.name -match "\.zip$") { $url = [string]$a.browser_download_url; break } }' + #13#10 +
    '  [System.IO.File]::WriteAllLines("' + GitResultFile + '", @($tag, $url), [System.Text.Encoding]::UTF8)' + #13#10 +
    '} catch {' + #13#10 +
    '  [System.IO.File]::WriteAllLines("' + GitResultFile + '", @("", ""), [System.Text.Encoding]::UTF8)' + #13#10 +
    '}' + #13#10;

  if not SaveStringToFile(GitWorkerScript, PowerShellCode, False) then
  begin
    LblGitStatus.Font.Color := clRed;
    LblGitStatus.Caption := CustomMessage('GitConnectionFailed');
    BtnGitRetry.Visible := True;
    GitCheckFinished := True;
    WizardForm.NextButton.Enabled := True;
    Exit;
  end;

  if Exec(
    ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
      GitWorkerScript + '"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) and (ResultCode = 0) then
  begin
    FinishGitHubReleaseCheck(True);
  end
  else
  begin
    FinishGitHubReleaseCheck(False);
  end;
end;

procedure FinishGitHubReleaseCheck(Success: Boolean);
var
  Lines: TArrayOfString;
begin
  OnlineVersionFound := False;
  RemoteVersionTag := '';
  RemoteDownloadUrl := '';

  if Success and FileExists(GitResultFile) and LoadStringsFromFile(GitResultFile, Lines) then
  begin
    if GetArrayLength(Lines) >= 2 then
    begin
      RemoteVersionTag := Trim(Lines[0]);
      RemoteDownloadUrl := Trim(Lines[1]);
      OnlineVersionFound := (RemoteVersionTag <> '') and
        (Pos('https://', RemoteDownloadUrl) = 1);
    end;
  end;

  if OnlineVersionFound then
  begin
    RbGitHub.Enabled := True;
    RbGitHub.Caption := CustomMessage('VersionGithub') + ' (' + RemoteVersionTag + ')';
    LblGitStatus.Font.Color := clGreen;
    LblGitStatus.Caption := FmtMessage(
      CustomMessage('GitLatestFound'), [RemoteVersionTag]);
    BtnGitRetry.Visible := False;

    // Automatically choose GitHub only if its version is newer.
    if CompareSemanticVersions(RemoteVersionTag, '{#MyAppVersion}') > 0 then
      RbGitHub.Checked := True
    else
      RbBundled.Checked := True;
  end
  else
  begin
    OnlineVersionFound := False;
    RbGitHub.Enabled := False;
    RbGitHub.Caption := CustomMessage('VersionGithub') + ' (недоступно)';
    RbBundled.Checked := True;
    LblGitStatus.Font.Color := clRed;
    LblGitStatus.Caption := CustomMessage('GitConnectionFailed');
    BtnGitRetry.Visible := True;
    BtnGitRetry.Enabled := True;
  end;

  GitCheckFinished := True;
  WizardForm.NextButton.Enabled := True;
  WizardForm.NextButton.Update();
end;

procedure OnGitRetryClick(Sender: TObject);
begin
  BtnGitRetry.Enabled := False;
  StartGitHubReleaseCheck();
end;

procedure CreateVersionSelectionPage();
var
  DescLabel: TLabel;
begin
  VersionPage := CreateCustomPage(wpWelcome,
    CustomMessage('VersionPageCaption'),
    CustomMessage('VersionPageSubCaption'));

  DescLabel := TLabel.Create(VersionPage);
  DescLabel.Parent := VersionPage.Surface;
  DescLabel.Left := ScaleX(0);
  DescLabel.Top := ScaleY(8);
  DescLabel.Width := VersionPage.SurfaceWidth - ScaleX(10);
  DescLabel.Height := ScaleY(36);
  DescLabel.AutoSize := False;
  DescLabel.WordWrap := True;
  DescLabel.Caption := CustomMessage('VersionPageDesc');

  RbBundled := TRadioButton.Create(VersionPage);
  RbBundled.Parent := VersionPage.Surface;
  RbBundled.Left := ScaleX(8);
  RbBundled.Top := ScaleY(52);
  RbBundled.Width := VersionPage.SurfaceWidth - ScaleX(16);
  RbBundled.Height := ScaleY(24);
  RbBundled.Caption := CustomMessage('VersionBundled');
  RbBundled.Checked := True;

  RbGitHub := TRadioButton.Create(VersionPage);
  RbGitHub.Parent := VersionPage.Surface;
  RbGitHub.Left := ScaleX(8);
  RbGitHub.Top := ScaleY(84);
  RbGitHub.Width := VersionPage.SurfaceWidth - ScaleX(16);
  RbGitHub.Height := ScaleY(24);
  RbGitHub.Caption := CustomMessage('VersionGithub');
  RbGitHub.Enabled := False;

  LblGitStatus := TLabel.Create(VersionPage);
  LblGitStatus.Parent := VersionPage.Surface;
  LblGitStatus.Left := ScaleX(32);
  LblGitStatus.Top := ScaleY(108);
  LblGitStatus.Width := ScaleX(375);
  LblGitStatus.Height := ScaleY(42);
  LblGitStatus.AutoSize := False;
  LblGitStatus.WordWrap := True;
  LblGitStatus.Caption := CustomMessage('GitChecking');

  BtnGitRetry := TButton.Create(VersionPage);
  BtnGitRetry.Parent := VersionPage.Surface;
  BtnGitRetry.Left := ScaleX(32);
  BtnGitRetry.Top := LblGitStatus.Top + LblGitStatus.Height + ScaleY(8);
  BtnGitRetry.Width := ScaleX(160);
  BtnGitRetry.Height := ScaleY(28);
  BtnGitRetry.Caption := CustomMessage('GitRetryBtn');
  BtnGitRetry.OnClick := @OnGitRetryClick;
  BtnGitRetry.Visible := False;
end;

procedure InitializeWizard();
begin
  DownloadPage := CreateDownloadPage(
    SetupMessage(msgWizardPreparing),
    SetupMessage(msgPreparingDesc), nil);
  DownloadPage.ShowBaseNameInsteadOfUrl := True;

  CreateVersionSelectionPage();
end;


function DetectReaperResourcePath(): String;
var
  Candidate: String;
  ExePath: String;
begin
  Result := '';

  // 1. Standard REAPER resource directory.
  Candidate := ExpandConstant('{userappdata}\REAPER');
  if FileExists(Candidate + '\reaper.ini') then
  begin
    Result := Candidate;
    Exit;
  end;

  // 2. Portable installs in common locations.
  Candidate := ExpandConstant('{userdocs}\REAPER');
  if FileExists(Candidate + '\reaper.ini') then
  begin
    Result := Candidate;
    Exit;
  end;

  Candidate := ExpandConstant('{autopf}\REAPER');
  if FileExists(Candidate + '\reaper.ini') then
  begin
    Result := Candidate;
    Exit;
  end;

  Candidate := ExpandConstant('{autopf}\REAPER (x64)');
  if FileExists(Candidate + '\reaper.ini') then
  begin
    Result := Candidate;
    Exit;
  end;

  // 3. Look up the registered REAPER executable.
  ExePath := '';
  if not RegQueryStringValue(
    HKLM,
    'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\reaper.exe',
    '',
    ExePath
  ) then
    if not RegQueryStringValue(
      HKCU,
      'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\reaper.exe',
      '',
      ExePath
    ) then
      ExePath := '';

  if ExePath <> '' then
  begin
    Candidate := ExtractFileDir(ExePath);

    // Portable install: resource files are beside reaper.exe.
    if FileExists(Candidate + '\reaper.ini') then
    begin
      Result := Candidate;
      Exit;
    end;

    // Standard install: resources are usually in AppData.
    Candidate := ExpandConstant('{userappdata}\REAPER');
    if DirExists(Candidate) then
    begin
      Result := Candidate;
      Exit;
    end;
  end;

  // 4. Fallback to the standard resource path if it exists.
  Candidate := ExpandConstant('{userappdata}\REAPER');
  if DirExists(Candidate) then
    Result := Candidate;
end;

// Check if a previous installation of NutNotes or old actions exist in the target directory
function HasPreviousInstallation(TargetReaperDir: String): Boolean;
var
  KbFile: String;
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := False;
  // 1. Check if NutNotes.lua or old folder exists
  if FileExists(TargetReaperDir + '\Scripts\NutNotes\NutNotes.lua') or
     DirExists(TargetReaperDir + '\Scripts\NutNotes') or
     FileExists(TargetReaperDir + '\Scripts\ReaperSubPlugin\ReaperSubPlugin.lua') or
     DirExists(TargetReaperDir + '\Scripts\ReaperSubPlugin') then
  begin
    Result := True;
    Exit;
  end;

  // 2. Check if reaper-kb.ini contains any NutNotes / launcher actions
  KbFile := TargetReaperDir + '\reaper-kb.ini';
  if FileExists(KbFile) and LoadStringsFromFile(KbFile, Lines) then
  begin
    for I := 0 to GetArrayLength(Lines) - 1 do
    begin
      if (Pos('_RS_NUTNOTES_LAUNCHER', Lines[I]) > 0) or
         (Pos('NutNotes.lua', Lines[I]) > 0) or
         (Pos('ReaperSubPlugin', Lines[I]) > 0) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
end;

// Pre-install cleanup: Remove old plugin files and actions
procedure CleanOldPluginAndActions(TargetReaperDir: String);
var
  KbFile: String;
  Lines: TArrayOfString;
  NewLines: TStringList;
  I: Integer;
  LineText: String;
  ScriptsDir, LegacyDir: String;
begin
  Log('CleanOldPluginAndActions: Cleaning old plugin files and actions in ' + TargetReaperDir);

  // 1. Remove old action entries from reaper-kb.ini
  KbFile := TargetReaperDir + '\reaper-kb.ini';
  if FileExists(KbFile) and LoadStringsFromFile(KbFile, Lines) then
  begin
    NewLines := TStringList.Create;
    try
      for I := 0 to GetArrayLength(Lines) - 1 do
      begin
        LineText := Lines[I];
        if (Pos('_RS_NUTNOTES_LAUNCHER', LineText) = 0) and
           (Pos('NutNotes.lua', LineText) = 0) and
           (Pos('ReaperSubPlugin', LineText) = 0) then
        begin
          NewLines.Add(LineText);
        end
        else
        begin
          Log('CleanOldPluginAndActions: Removed legacy action line: ' + LineText);
        end;
      end;
      NewLines.SaveToFile(KbFile);
    finally
      NewLines.Free;
    end;
  end;

  // 2. Clean old script files in Scripts\NutNotes
  ScriptsDir := TargetReaperDir + '\Scripts\NutNotes';
  if DirExists(ScriptsDir) then
  begin
    DelTree(ScriptsDir + '\modules', True, True, True);
    DelTree(ScriptsDir + '\assets', True, True, True);
    DelTree(ScriptsDir + '\examples', True, True, True);
    DelTree(ScriptsDir + '\test_samples', True, True, True);
    DelTree(ScriptsDir + '\tests', True, True, True);

    DeleteFile(ScriptsDir + '\NutNotes.lua');
    DeleteFile(ScriptsDir + '\ReaperSubPlugin.lua');
    DeleteFile(ScriptsDir + '\acorn.png');
    DeleteFile(ScriptsDir + '\README.md');
  end;

  // 3. Clean legacy folder Scripts\ReaperSubPlugin if present
  LegacyDir := TargetReaperDir + '\Scripts\ReaperSubPlugin';
  if DirExists(LegacyDir) then
  begin
    DelTree(LegacyDir, True, True, True);
  end;

  // NOTE: Settings file {app}\reaper-extstate.ini is preserved intact!
end;

// 1. Register Action in reaper-kb.ini
procedure RegisterActionInKbIni(ReaperDir: String);
var
  KbFile: String;
  Lines: TArrayOfString;
  I: Integer;
  AlreadyExists: Boolean;
  ActionLine: String;
begin
  KbFile := ReaperDir + '\reaper-kb.ini';
  ActionLine := 'SCR 4 0 _RS_NUTNOTES_LAUNCHER "Script: NutNotes.lua" "NutNotes/NutNotes.lua"';
  AlreadyExists := False;

  if FileExists(KbFile) then
  begin
    if LoadStringsFromFile(KbFile, Lines) then
    begin
      for I := 0 to GetArrayLength(Lines) - 1 do
      begin
        if (Pos('_RS_NUTNOTES_LAUNCHER', Lines[I]) > 0) or
           (Pos('NutNotes/NutNotes.lua', Lines[I]) > 0) then
        begin
          AlreadyExists := True;
          Break;
        end;
      end;
    end;
  end;

  if not AlreadyExists then
  begin
    SaveStringToFile(KbFile, #13#10 + ActionLine + #13#10, True);
    Log('Registered NutNotes action in ' + KbFile);
  end;
end;

// 2. Add button to reaper-menu.ini [Main toolbar]
procedure AddButtonToMenuIni(ReaperDir: String);
var
  MenuFile: String;
  Lines: TArrayOfString;
  I, MainToolbarIndex, MaxItemNum: Integer;
  InMainToolbar: Boolean;
  LineText, ItemKey: String;
  NewLines: TStringList;
  AlreadyInToolbar: Boolean;
  NumStr: String;
  CurNum: Integer;
begin
  MenuFile := ReaperDir + '\reaper-menu.ini';
  if not FileExists(MenuFile) then
  begin
    NewLines := TStringList.Create;
    try
      NewLines.Add('[Main toolbar]');
      NewLines.Add('default=095da8527a5acf0e');
      NewLines.Add('title=Main toolbar');
      NewLines.Add('item_0=40023 New project...');
      NewLines.Add('item_1=40025 Open project...');
      NewLines.Add('item_2=40026 Save project');
      NewLines.Add('item_3=40021 Project settings...');
      NewLines.Add('item_4=40029 Undo');
      NewLines.Add('item_5=40030 Redo');
      NewLines.Add('item_6=40364 Enable metronome');
      NewLines.Add('item_7=-1');
      NewLines.Add('item_8=42616 Marquee selection');
      NewLines.Add('item_9=-1');
      NewLines.Add('item_10=40041 Enable auto-crossfade');
      NewLines.Add('item_11=1156 Enable item grouping and track media/razor edit grouping');
      NewLines.Add('item_12=1155 Enable ripple editing');
      NewLines.Add('item_13=40070 Move envelope points with media items');
      NewLines.Add('item_14=40145 Show arrange view grid');
      NewLines.Add('item_15=1157 Enable snapping');
      NewLines.Add('item_16=1135 Enable locking');
      NewLines.Add('item_17=-1');
      NewLines.Add('item_18=42618 Razor editing');
      NewLines.Add('item_19=_RS_NUTNOTES_LAUNCHER');
      NewLines.Add('icon_19=nutnotes_toolbar.png');
      NewLines.Add('text_19=NutNotes');
      NewLines.SaveToFile(MenuFile);
      Log('Created reaper-menu.ini with NutNotes toolbar button');
    finally
      NewLines.Free;
    end;
    Exit;
  end;

  if not LoadStringsFromFile(MenuFile, Lines) then Exit;

  InMainToolbar := False;
  MainToolbarIndex := -1;
  MaxItemNum := -1;
  AlreadyInToolbar := False;

  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    LineText := Trim(Lines[I]);
    if Pos('[Main toolbar]', LineText) = 1 then
    begin
      InMainToolbar := True;
      MainToolbarIndex := I;
    end
    else if InMainToolbar and (Length(LineText) > 0) and (LineText[1] = '[') then
    begin
      InMainToolbar := False;
    end
    else if InMainToolbar then
    begin
      if (Pos('_RS_NUTNOTES_LAUNCHER', LineText) > 0) or
         (Pos('nutnotes_toolbar.png', LineText) > 0) then
      begin
        AlreadyInToolbar := True;
      end;
      if Pos('item_', LineText) = 1 then
      begin
        NumStr := Copy(LineText, 6, Pos('=', LineText) - 6);
        CurNum := StrToIntDef(NumStr, -1);
        if CurNum > MaxItemNum then
          MaxItemNum := CurNum;
      end;
    end;
  end;

  if AlreadyInToolbar then Exit;

  NewLines := TStringList.Create;
  try
    InMainToolbar := False;
    if MainToolbarIndex = -1 then
    begin
      for I := 0 to GetArrayLength(Lines) - 1 do
        NewLines.Add(Lines[I]);
      NewLines.Add('');
      NewLines.Add('[Main toolbar]');
      NewLines.Add('default=095da8527a5acf0e');
      NewLines.Add('title=Main toolbar');
      NewLines.Add('item_0=40023 New project...');
      NewLines.Add('item_1=40025 Open project...');
      NewLines.Add('item_2=40026 Save project');
      NewLines.Add('item_3=40021 Project settings...');
      NewLines.Add('item_4=40029 Undo');
      NewLines.Add('item_5=40030 Redo');
      NewLines.Add('item_6=40364 Enable metronome');
      NewLines.Add('item_7=-1');
      NewLines.Add('item_8=42616 Marquee selection');
      NewLines.Add('item_9=-1');
      NewLines.Add('item_10=40041 Enable auto-crossfade');
      NewLines.Add('item_11=1156 Enable item grouping and track media/razor edit grouping');
      NewLines.Add('item_12=1155 Enable ripple editing');
      NewLines.Add('item_13=40070 Move envelope points with media items');
      NewLines.Add('item_14=40145 Show arrange view grid');
      NewLines.Add('item_15=1157 Enable snapping');
      NewLines.Add('item_16=1135 Enable locking');
      NewLines.Add('item_17=-1');
      NewLines.Add('item_18=42618 Razor editing');
      NewLines.Add('item_19=_RS_NUTNOTES_LAUNCHER');
      NewLines.Add('icon_19=nutnotes_toolbar.png');
      NewLines.Add('text_19=NutNotes');
    end
    else
    begin
      MaxItemNum := MaxItemNum + 1;
      for I := 0 to GetArrayLength(Lines) - 1 do
      begin
        LineText := Trim(Lines[I]);
        if (I > MainToolbarIndex) and InMainToolbar and (Length(LineText) > 0) and (LineText[1] = '[') then
        begin
          ItemKey := 'item_' + IntToStr(MaxItemNum);
          NewLines.Add(ItemKey + '=_RS_NUTNOTES_LAUNCHER');
          NewLines.Add('icon_' + IntToStr(MaxItemNum) + '=nutnotes_toolbar.png');
          NewLines.Add('text_' + IntToStr(MaxItemNum) + '=NutNotes');
          InMainToolbar := False;
        end;
        if Pos('[Main toolbar]', LineText) = 1 then
          InMainToolbar := True;
        NewLines.Add(Lines[I]);
      end;
      if InMainToolbar then
      begin
        ItemKey := 'item_' + IntToStr(MaxItemNum);
        NewLines.Add(ItemKey + '=_RS_NUTNOTES_LAUNCHER');
        NewLines.Add('icon_' + IntToStr(MaxItemNum) + '=nutnotes_toolbar.png');
        NewLines.Add('text_' + IntToStr(MaxItemNum) + '=NutNotes');
      end;
    end;
    NewLines.SaveToFile(MenuFile);
    Log('Added NutNotes button to Main Toolbar in ' + MenuFile);
  finally
    NewLines.Free;
  end;
end;

// 3. Auto-start integration in Scripts\__startup.lua
procedure ConfigureStartupScript(ReaperDir: String; EnableStartup: Boolean);
var
  StartupFile: String;
  SL: TStringList;
  Content: String;
  StartupBlock: String;
  StartPos, EndPos: Integer;
begin
  StartupFile := ReaperDir + '\Scripts\__startup.lua';
  SL := TStringList.Create;
  try
    if FileExists(StartupFile) then
      SL.LoadFromFile(StartupFile);
    Content := SL.Text;

    // Strip existing NutNotes startup block if present
    StartPos := Pos('-- >>> NutNotes Startup >>>', Content);
    while StartPos > 0 do
    begin
      EndPos := Pos('-- <<< NutNotes Startup <<<', Content);
      if EndPos > 0 then
        Delete(Content, StartPos, (EndPos + Length('-- <<< NutNotes Startup <<<')) - StartPos)
      else
        Break;
      StartPos := Pos('-- >>> NutNotes Startup >>>', Content);
    end;

    Content := Trim(Content);

    if EnableStartup then
    begin
      StartupBlock := #13#10 +
        '-- >>> NutNotes Startup >>>' + #13#10 +
        'reaper.defer(function()' + #13#10 +
        '  local res = reaper.GetResourcePath()' + #13#10 +
        '  local cmd_id = reaper.NamedCommandLookup("_RS_NUTNOTES_LAUNCHER")' + #13#10 +
        '  if not cmd_id or cmd_id <= 0 then' + #13#10 +
        '    cmd_id = reaper.NamedCommandLookup("_RS2dc2e136e0d96f0d14a4948732a1c5629b86ef37")' + #13#10 +
        '  end' + #13#10 +
        '  if cmd_id and cmd_id > 0 then' + #13#10 +
        '    reaper.Main_OnCommand(cmd_id, 0)' + #13#10 +
        '  else' + #13#10 +
        '    local p = res .. "/Scripts/NutNotes/NutNotes.lua"' + #13#10 +
        '    local fl = io.open(p, "r")' + #13#10 +
        '    if fl then' + #13#10 +
        '      fl:close()' + #13#10 +
        '      dofile(p)' + #13#10 +
        '    end' + #13#10 +
        '  end' + #13#10 +
        'end)' + #13#10 +
        '-- <<< NutNotes Startup <<<' + #13#10;

      if Length(Content) > 0 then
        SL.Text := Content + #13#10 + StartupBlock
      else
        SL.Text := StartupBlock;

      SL.SaveToFile(StartupFile);
      Log('Configured startup script in ' + StartupFile);
    end
    else
    begin
      SL.Text := Content;
      SL.SaveToFile(StartupFile);
    end;
  finally
    SL.Free;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  SelectedPath: String;
begin
  Result := True;

  if CurPageID = VersionPage.ID then
  begin
    if not GitCheckFinished then
    begin
      Result := False;
      Exit;
    end;
    UseOnlineDownload := RbGitHub.Checked and OnlineVersionFound and (RemoteDownloadUrl <> '');
  end;

  if (CurPageID = wpSelectDir) and (not WizardSilent()) then
  begin
    SelectedPath := ExpandConstant('{app}');
    if not FileExists(SelectedPath + '\reaper.ini') and
       not FileExists(SelectedPath + '\reaper.exe') and
       not DirExists(SelectedPath + '\Scripts') then
    begin
      if MsgBox(
        'Предупреждение: Выбранная папка не похожа на папку настроек или установки REAPER (в ней нет reaper.ini или папки Scripts).' + #13#10 + #13#10 +
        'Обычно папка ресурсов REAPER находится по пути:' + #13#10 +
        ExpandConstant('{userappdata}\REAPER') + #13#10#13#10 +
        'Вы уверены, что хотите установить NutNotes в эту папку?',
        mbConfirmation, MB_YESNO) = idNo then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;

  if CurPageID = wpReady then
  begin
    SelectedPath := ExpandConstant('{app}');
    if SelectedPath <> LastWarnedPath then
      OldVersionWarningConfirmed := False;

    if HasPreviousInstallation(SelectedPath) and (not OldVersionWarningConfirmed) and (not WizardSilent()) then
    begin
      if MsgBox(CustomMessage('WarnOldVersion'), mbConfirmation, MB_YESNO or MB_DEFBUTTON1) <> idYes then
      begin
        Result := False;
        Exit;
      end;
      OldVersionWarningConfirmed := True;
      LastWarnedPath := SelectedPath;
    end;

    if UseOnlineDownload and (RemoteDownloadUrl <> '') then
    begin
      DownloadedZipPath := ExpandConstant('{tmp}\nutnotes_latest.zip');
      ExtractedTempDir := ExpandConstant('{tmp}\nutnotes_extracted');
      DownloadPage.Clear;
      DownloadPage.Add(RemoteDownloadUrl, 'nutnotes_latest.zip', '');
      DownloadPage.Show;
      try
        try
          DownloadPage.Download;
          Result := True;
        except
          if MsgBox('Не удалось загрузить обновление с GitHub.' + #13#10 +
                    'Продолжить установку вшитой версии v{#MyAppVersion}?', mbError, MB_YESNO) = idYes then
          begin
            UseOnlineDownload := False;
            Result := True;
          end
          else
          begin
            Result := False;
            Exit;
          end;
        end;
      finally
        DownloadPage.Hide;
      end;
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  DetectedDir: String;
begin
  if (CurPageID = VersionPage.ID) then
  begin
    if not GitCheckFinished then
    begin
      WizardForm.NextButton.Enabled := False;
      WizardForm.Refresh();
    end;

    if not GitCheckPerformed then
    begin
      GitCheckPerformed := True;
      StartGitHubReleaseCheck();
    end;
  end;

  if (CurPageID = wpSelectDir) and (not DirPrepopulated) then
  begin
    DirPrepopulated := True;
    DetectedDir := DetectReaperResourcePath();
    if (DetectedDir <> '') and DirExists(DetectedDir) then
      WizardForm.DirEdit.Text := DetectedDir
    else if WizardForm.DirEdit.Text = '' then
      WizardForm.DirEdit.Text := ExpandConstant('{userappdata}\REAPER');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  TargetReaperDir: String;
  CmdOut: Integer;
begin
  TargetReaperDir := ExpandConstant('{app}');

  // Pre-install: Remove old plugin version files and actions before copying new files
  if CurStep = ssInstall then
  begin
    WizardForm.StatusLabel.Caption := CustomMessage('StatusCleaning');
    CleanOldPluginAndActions(TargetReaperDir);
  end;

  if CurStep = ssPostInstall then
  begin
    // If user chose online download and archive was downloaded
    if UseOnlineDownload and FileExists(DownloadedZipPath) then
    begin
      WizardForm.StatusLabel.Caption := 'Развертывание NutNotes с GitHub...';
      CreateDir(ExtractedTempDir);
      // Extract archive and merge UserPlugins and Scripts directly into target REAPER resource folder
      Exec('powershell.exe', '-NoProfile -Command "Expand-Archive -Path ''' + DownloadedZipPath + ''' -DestinationPath ''' + ExtractedTempDir + ''' -Force"', '', SW_HIDE, ewWaitUntilTerminated, CmdOut);
      Exec('powershell.exe', '-NoProfile -Command "$src = if (Test-Path ''' + ExtractedTempDir + '\Scripts'') { ''' + ExtractedTempDir + ''' } else { (Get-ChildItem ''' + ExtractedTempDir + ''' -Directory | Select-Object -First 1).FullName }; Copy-Item -Path ($src + ''\*'') -Destination ''' + TargetReaperDir + ''' -Recurse -Force"', '', SW_HIDE, ewWaitUntilTerminated, CmdOut);
      // Clean up temporary downloaded zip archive and extracted folders immediately
      DeleteFile(DownloadedZipPath);
      DelTree(ExtractedTempDir, True, True, True);
    end;

    // Always ensure Action is registered in reaper-kb.ini
    RegisterActionInKbIni(TargetReaperDir);

    // Apply Toolbar button if checked
    if WizardIsTaskSelected('toolbar') then
    begin
      AddButtonToMenuIni(TargetReaperDir);
    end;

    // Apply Autostart if checked
    if WizardIsTaskSelected('autostart') then
    begin
      ConfigureStartupScript(TargetReaperDir, True);
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  TargetReaperDir: String;
  KbFile: String;
  Lines: TArrayOfString;
  NewLines: TStringList;
  I: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    TargetReaperDir := ExtractFilePath(ExpandConstant('{uninstallexe}'));
    if (Length(TargetReaperDir) > 0) and (TargetReaperDir[Length(TargetReaperDir)] = '\') then
      SetLength(TargetReaperDir, Length(TargetReaperDir) - 1);

    // 1. Remove Action from reaper-kb.ini
    KbFile := TargetReaperDir + '\reaper-kb.ini';
    if FileExists(KbFile) and LoadStringsFromFile(KbFile, Lines) then
    begin
      NewLines := TStringList.Create;
      try
        for I := 0 to GetArrayLength(Lines) - 1 do
        begin
          if (Pos('_RS_NUTNOTES_LAUNCHER', Lines[I]) = 0) and
             (Pos('NutNotes.lua', Lines[I]) = 0) then
            NewLines.Add(Lines[I]);
        end;
        NewLines.SaveToFile(KbFile);
      finally
        NewLines.Free;
      end;
    end;

    // 2. Remove Autostart from Scripts\__startup.lua
    ConfigureStartupScript(TargetReaperDir, False);
  end;
end;

procedure DeinitializeSetup();
begin
end;
