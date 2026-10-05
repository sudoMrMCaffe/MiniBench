# Katalog des Moduls Optimierung (ab v2.8): alle Einstellungen des Windows Optimisation Pack (Marvin700), seiner
# Sophia-Script-Konfiguration (Windows 10 und 11) und seiner O&O-ShutUp10-Auswahl (ooshutup.cfg, nur Einträge mit +),
# nativ umgesetzt, zusammengeführt und nach Kategorien gruppiert. Sophia Script und O&O ShutUp10++ laufen nicht mehr.
#
# Eintrag:  Id, Kat (Schlüssel aus Kategorien), Titel, Text, Risiko (Aendern = protokolliert und rückgängig machbar,
#           Eingriff = ohne automatisches Rückgängig), Neustart (nie, moeglich, immer), Vorlagen (M = Minimal,
#           S = Standard, E = Erweitert; leer = nur von Hand), Quelle (Herkunft im Pack), optional Hinweis, Verwaltet
#           ($true = berührt Gruppenrichtlinien oder zentrale Verwaltung; auf Domänen-PCs nie in einer Vorlage),
#           Bedingung (Win10, Win11, Desktop, Nvidia, Terminal) und Minuten (geschätzte Dauer).
# Aktionen: Reg (Pfad, Name, Wert, Typ; HKCU meint den angemeldeten Benutzer, {SID} dessen SID),
#           RegKey (Pfad, Werte: Schlüssel neu anlegen, Rückgängig löscht ihn wieder), Dienst (Name, Start),
#           Aufgabe (Name, optional Pfad; Name * = alle Aufgaben des Pfads), Feature (Name), Capability (Muster),
#           App (Muster), Sonder (Name des eigenen Ablaufs, optional Werte).
@{
    Katalog     = 1
    Kategorien  = @(
        @{ Key = 'Datenschutz';  Titel = 'Datenschutz und Telemetrie'; Text = 'Diagnosedaten, Fehlerberichte, Werbe-ID und andere Datenübertragungen an Microsoft.' }
        @{ Key = 'Werbung';      Titel = 'Werbung, Tipps und Vorschläge'; Text = 'Empfehlungen, Tipps, App-Vorschläge und automatisch installierte Apps.' }
        @{ Key = 'KI';           Titel = 'Suche, Cortana, Copilot und KI'; Text = 'Websuche im Startmenü, Cortana, Copilot, Recall und KI-Funktionen in Paint.' }
        @{ Key = 'Berechtigung'; Titel = 'App-Berechtigungen, Verlauf und Synchronisierung'; Text = 'Zugriff von Apps auf Konto, Diagnose, Standort und Bewegung, Aktivitätsverlauf, Zwischenablage und Synchronisierung.' }
        @{ Key = 'Hintergrund';  Titel = 'Dienste und geplante Aufgaben'; Text = 'Dienste und Aufgaben, die im Hintergrund laufen und auf den meisten PCs nicht gebraucht werden.' }
        @{ Key = 'Funktionen';   Titel = 'Windows-Funktionen und Zusatzfeatures'; Text = 'Optionale Windows-Funktionen abschalten und selten gebrauchte Zusatzfeatures entfernen.' }
        @{ Key = 'Apps';         Titel = 'Vorinstallierte Apps entfernen'; Text = 'Apps aus dem Microsoft Store, die Windows mitbringt. Zurück nur über den Store.' }
        @{ Key = 'Bedienung';    Titel = 'Explorer, Taskleiste und Start'; Text = 'Dateiendungen, Schnellzugriff, Taskleiste, Startmenü und Kontextmenüs.' }
        @{ Key = 'Darstellung';  Titel = 'Darstellung und persönliche Vorlieben'; Text = 'Geschmackssache: dunkler Modus, Taskleiste links, Laufwerksname und Ähnliches.' }
        @{ Key = 'Leistung';     Titel = 'Leistung, Spiele und Energie'; Text = 'Indizierung, Maus, Spiele-Prioritäten, Grafikplanung, Energieplan und Ruhezustand.' }
        @{ Key = 'Update';       Titel = 'Windows Update, Edge und OneDrive'; Text = 'Übermittlungsoptimierung, Neustartverhalten, Updates anderer Microsoft-Produkte, Edge im Hintergrund und OneDrive.' }
        @{ Key = 'Sicherheit';   Titel = 'Sicherheit und Fernzugriff'; Text = 'Netzwerkschutz, unerwünschte Apps, Remoteunterstützung, Remotedesktop und verschlüsseltes DNS.' }
        @{ Key = 'Grafik';       Titel = 'Grafiktreiber'; Text = 'Grafiktreiber restlos entfernen (DDU) und NVIDIA-Profil setzen.' }
    )
    Eintraege   = @(
        # ------------------------------------------------------------------ Datenschutz und Telemetrie
        @{ Id = 'TelemetrieMinimal'; Kat = 'Datenschutz'; Titel = 'Diagnosedaten auf das Minimum'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'Pack Registry, Sophia DiagnosticDataLevel, O&O S003'
           Text = 'Erlaubt Windows nur noch die erforderlichen Diagnosedaten (Richtlinie AllowTelemetry 0; Home und Pro behandeln 0 wie Erforderlich).'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'MaxTelemetryAllowed'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'; Name = 'ShowedToastAtLevel'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitEnhancedDiagnosticDataWindowsAnalytics'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'TelemetrieDienste'; Kat = 'Datenschutz'; Titel = 'Telemetriedienste abschalten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Dienste und Registry, Sophia DiagTrackService'
           Text = 'Benutzererfahrung und Telemetrie (DiagTrack), WAP-Push (dmwappushservice) sowie die Diagnosedienste werden beendet und deaktiviert.'
           Hinweis = 'Ohne DiagTrack gibt es keine Xbox-Erfolge mehr.'
           Aktionen = @(
               @{ Art = 'Dienst'; Name = 'DiagTrack'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'dmwappushservice'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'diagnosticshub.standardcollector.service'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'diagsvc'; Start = 'Disabled' }
           ) }
        @{ Id = 'TelemetrieDiagnoseprotokolle'; Kat = 'Datenschutz'; Titel = 'Diagnoseprotokolle und OneSettings nicht übertragen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O U006, U007'
           Text = 'Keine Sammlung von Diagnoseprotokollen und kein Herunterladen von OneSettings-Konfigurationen.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'LimitDiagnosticLogCollection'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DisableOneSettingsDownloads'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'Fehlerberichte'; Kat = 'Datenschutz'; Titel = 'Windows-Fehlerberichterstattung aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Dienste, Sophia ErrorReporting, O&O P069'
           Text = 'Abstürze werden nicht mehr an Microsoft gemeldet: Richtlinie, Benutzerschalter, Aufgabe QueueReporting und die Dienste WerSvc und wercplsupport.'
           Hinweis = 'Die Ereignisprotokolle mit den Absturzdaten bleiben erhalten, die Diagnose von Leos Minibench wertet sie weiter aus.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Aufgabe'; Name = 'QueueReporting' }
               @{ Art = 'Dienst'; Name = 'WerSvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'wercplsupport'; Start = 'Disabled' }
           ) }
        @{ Id = 'Feedback'; Kat = 'Datenschutz'; Titel = 'Keine Feedback-Anfragen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia FeedbackFrequency, O&O M001, M022'
           Text = 'Windows fragt nie mehr nach Feedback.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DoNotShowFeedbackNotifications'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'WerbeId'; Kat = 'Datenschutz'; Titel = 'Werbe-ID abschalten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia AdvertisingID, O&O P005, P006'
           Text = 'Apps bekommen keine Werbe-ID für personalisierte Werbung.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'MassgeschneiderteErfahrung'; Kat = 'Datenschutz'; Titel = 'Keine Tipps und Werbung aus Diagnosedaten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia TailoredExperiences, O&O U004, U005'
           Text = 'Microsoft nutzt Diagnosedaten nicht für persönliche Tipps, Werbung und Empfehlungen.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableTailoredExperiencesWithDiagnosticData'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'Sprachliste'; Kat = 'Datenschutz'; Titel = 'Websites sehen die Sprachliste nicht'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia LanguageListAccess, O&O P015'
           Text = 'Websites können über die Sprachliste keine lokal angepassten Inhalte anbieten.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\International\User Profile'; Name = 'HttpAcceptLanguageOptOut'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'Anmeldeinfo'; Kat = 'Datenschutz'; Titel = 'Anmeldedaten nicht zum Einrichten nach Updates nutzen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia SigninInfo'
           Text = 'Nach einem Update meldet Windows den Benutzer nicht mehr automatisch an, um die Einrichtung abzuschließen.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserARSO\{SID}'; Name = 'OptOut'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'Handschrift'; Kat = 'Datenschutz'; Titel = 'Handschrift- und Eingabedaten nicht teilen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O P001, P002, P008, P068'
           Text = 'Keine Weitergabe von Handschriftdaten, Handschrift-Fehlerberichten und Tippinformationen, keine Textvorschläge der Bildschirmtastatur.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC'; Name = 'PreventHandwritingDataSharing'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports'; Name = 'PreventHandwritingErrorReports'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Input\TIPC'; Name = 'Enabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\TabletTip\1.7'; Name = 'EnableTextPrediction'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Inventar'; Kat = 'Datenschutz'; Titel = 'Inventarsammlung und Kompatibilitätstelemetrie aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O P003, U001, S002, P027'
           Text = 'Kein Inventory Collector, keine Anwendungstelemetrie, keine Schrittaufzeichnung und kein Programm zur Verbesserung der Benutzerfreundlichkeit (CEIP).'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableInventory'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'AITEnable'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Name = 'DisableUAR'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Name = 'CEIPEnable'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Insiderseite'; Kat = 'Datenschutz'; Titel = 'Seite Windows-Insider-Programm ausblenden'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Pack Registry'
           Text = 'Blendet die Insider-Seite in den Einstellungen aus.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\UI\Visibility'; Name = 'HideInsiderPage'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'Nachrichtensicherung'; Kat = 'Datenschutz'; Titel = 'Textnachrichten nicht in der Cloud sichern'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O P028'
           Text = 'Keine Sicherung von Textnachrichten in die Cloud.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Messaging'; Name = 'AllowMessageSync'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'BluetoothWerbung'; Kat = 'Datenschutz'; Titel = 'Keine Werbung über Bluetooth'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O P026'
           Text = 'Bluetooth-Geräte dürfen keine Werbung ausstrahlen lassen.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Bluetooth'; Name = 'AllowAdvertising'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'MediaPlayerDiagnose'; Kat = 'Datenschutz'; Titel = 'Windows Media Player ohne Nutzungsdaten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O M024'
           Text = 'Der Windows Media Player sendet keine Nutzungsdaten.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\MediaPlayer\Preferences'; Name = 'UsageTracking'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'KmsOnline'; Kat = 'Datenschutz'; Titel = 'KMS-Onlineprüfung (AVS) aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O M012'
           Text = 'Windows schickt nach einer KMS-Aktivierung kein Ticket zur Onlineprüfung an Microsoft. Die Aktivierung selbst bleibt unberührt.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform'; Name = 'NoGenTicket'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'Standort'; Kat = 'Datenschutz'; Titel = 'Standortdienste und Sensoren aus'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O L001, L003, L004, L005'
           Text = 'Ortung, Ortung per Skript, Lage- und Ortungssensoren sowie der Geolocation-Dienst (lfsvc) werden abgeschaltet.'
           Hinweis = 'Automatische Zeitzone, Wo ist mein Gerät und Wetter mit Standort funktionieren danach nicht mehr.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; Name = 'DisableLocation'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; Name = 'DisableLocationScripting'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'; Name = 'DisableSensors'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Dienst'; Name = 'lfsvc'; Start = 'Disabled' }
           ) }
        # ------------------------------------------------------------------ Werbung, Tipps und Vorschläge
        @{ Id = 'TippsVorschlaege'; Kat = 'Werbung'; Titel = 'Tipps, Tricks und Vorschläge aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia WindowsTips, AppSuggestions, O&O P066, M005, P065, M006, P064'
           Text = 'Keine Tipps beim Arbeiten mit Windows, keine App-Vorschläge im Startmenü und in der Zeitachse.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353698Enabled'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Willkommen'; Kat = 'Werbung'; Titel = 'Kein Willkommensbildschirm und kein Einrichtungshinweis nach Updates'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia WindowsWelcomeExperience, WhatsNewInWindows, O&O P070'
           Text = 'Nach Updates keine Neuigkeiten-Seite und keine Aufforderung, die Einrichtung des Geräts abzuschließen.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-310093Enabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; Name = 'ScoobeSystemSettingEnabled'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'EinstellungenVorschlaege'; Kat = 'Werbung'; Titel = 'Keine vorgeschlagenen Inhalte in den Einstellungen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia SettingsSuggestedContent, O&O P067'
           Text = 'Die Einstellungen-App zeigt keine vorgeschlagenen Inhalte mehr.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338393Enabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353696Enabled'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'AppsStillInstallieren'; Kat = 'Werbung'; Titel = 'Keine automatisch installierten Vorschlags-Apps'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'Sophia AppsSilentInstalling, O&O M004'
           Text = 'Windows installiert keine empfohlenen Store-Apps mehr von selbst (Verbraucherfunktionen aus).'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsConsumerFeatures'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'Sperrbildschirm'; Kat = 'Werbung'; Titel = 'Sperrbildschirm ohne Spotlight, Tipps und Benachrichtigungen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O K001, K002, K005, M028'
           Text = 'Kein Windows-Blickpunkt, keine Fakten und Tipps auf dem Sperrbildschirm, keine Benachrichtigungen darauf und kein Blickpunkt-Symbol auf dem Desktop.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'; Name = 'DisableWindowsSpotlightFeatures'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenOverlayEnabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338387Enabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'; Name = 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'; Name = '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'Sperrkamera'; Kat = 'Werbung'; Titel = 'Keine Kamera auf dem Sperrbildschirm'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O P004'
           Text = 'Die Kamera lässt sich auf dem Sperrbildschirm nicht mehr starten.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'; Name = 'NoLockScreenCamera'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'ExplorerWerbung'; Kat = 'Werbung'; Titel = 'Keine OneDrive-Werbung im Explorer'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia OneDriveFileExplorerAd, O&O M010'
           Text = 'Der Explorer zeigt keine Hinweise des Synchronisierungsanbieters mehr.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSyncProviderNotifications'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'Smartphone'; Kat = 'Werbung'; Titel = 'Smartphone-Link und Vorschläge für Mobilgeräte aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O D001, D002, D003, D104'
           Text = 'Kein Verbinden mit dem Smartphone und keine Vorschläge dazu.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableMmx'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Mobility'; Name = 'OptedIn'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'XboxTipps'; Kat = 'Werbung'; Titel = 'Keine Tipps der Spieleleiste'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia XboxGameTips'
           Text = 'Die Xbox Game Bar zeigt beim Spielstart keine Tipps.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\GameBar'; Name = 'ShowStartupPanel'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'NeueAppHinweis'; Kat = 'Werbung'; Titel = 'Kein Hinweis auf neu installierte Apps'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Bedingung = 'Win10'
           Quelle = 'Sophia NewAppInstalledNotification (Windows 10)'
           Text = 'Kein Hinweis "Neue App kann diesen Dateityp öffnen".'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name = 'NoNewAppAlert'; Wert = 1; Typ = 'DWord' } ) }
        # ------------------------------------------------------------------ Suche, Cortana, Copilot und KI
        @{ Id = 'Websuche'; Kat = 'KI'; Titel = 'Keine Websuche (Bing) im Startmenü'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia BingSearch, O&O C008, C009, C011, M003'
           Text = 'Die Suche im Startmenü und in der Taskleiste durchsucht nur noch den PC, nicht Bing und keine Cloud-Inhalte.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'BingSearchEnabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'ConnectedSearchUseWeb'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCloudSearch'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Suchhighlights'; Kat = 'KI'; Titel = 'Suchhighlights aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia SearchHighlights, O&O C015'
           Text = 'Das Suchfeld zeigt keine wechselnden Highlights und Themen des Tages.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; Name = 'IsDynamicSearchBoxEnabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'EnableDynamicContentInWSB'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Cortana'; Kat = 'KI'; Titel = 'Cortana aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O C012, C007, C014'
           Text = 'Cortana ist nicht erlaubt, auch nicht über dem Sperrbildschirm, und die Suche nutzt keinen Standort.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortanaAboveLock'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowSearchToUseLocation'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Spracherkennung'; Kat = 'KI'; Titel = 'Keine Online-Spracherkennung und Eingabepersonalisierung'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O C002, C013, C010, W011'
           Text = 'Keine Online-Spracherkennung, kein Lernen aus Eingaben, keine automatischen Updates der Sprachmodelle.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'; Name = 'AllowInputPersonalization'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name = 'HasAccepted'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Speech'; Name = 'AllowSpeechModelUpdate'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Copilot'; Kat = 'KI'; Titel = 'Copilot aus und Schaltfläche entfernen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia WindowsAI, O&O C101, C201, C102, C104'
           Text = 'Windows Copilot ist abgeschaltet, die Schaltfläche fehlt in der Taskleiste und Bing Chat ist nicht freigeschaltet.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCopilotButton'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\Shell\Copilot\BingChat'; Name = 'IsUserEligible'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Recall'; Kat = 'KI'; Titel = 'Recall und Click to Do aus'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'MSE'
           Quelle = 'Sophia WindowsAI, O&O C103, C203, C204'
           Text = 'Keine Bildschirmaufnahmen durch Recall, Recall wird nicht bereitgestellt, Click to Do ist aus.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'AllowRecallEnablement'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableClickToDo'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'PaintKI'; Kat = 'KI'; Titel = 'KI-Funktionen in Paint und Editor aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia WindowsAI, O&O C205, C206, C207'
           Text = 'Image Creator, Cocreator und generatives Füllen in Paint sowie die KI-Funktionen im Editor sind abgeschaltet.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableImageCreator'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableCocreator'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; Name = 'DisableGenerativeFill'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\WindowsNotepad'; Name = 'DisableAIFeatures'; Wert = 1; Typ = 'DWord' }
           ) }
        # ------------------------------------------------------------------ App-Berechtigungen, Verlauf und Synchronisierung
        @{ Id = 'Aktivitaetsverlauf'; Kat = 'Berechtigung'; Titel = 'Aktivitätsverlauf aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O A001, A002, A003'
           Text = 'Windows zeichnet keine Aktivitäten auf, speichert keinen Verlauf und lädt keinen hoch.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'UploadUserActivities'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Zwischenablage'; Kat = 'Berechtigung'; Titel = 'Zwischenablageverlauf und Cloud-Zwischenablage aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O A004, A005, A006'
           Text = 'Kein Verlauf mit Win+V und keine Übertragung der Zwischenablage auf andere Geräte.'
           Hinweis = 'Wer den Verlauf der Zwischenablage (Win+V) nutzt, lässt diesen Eintrag weg.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'AllowClipboardHistory'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Clipboard'; Name = 'EnableClipboardHistory'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'AllowCrossDeviceClipboard'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'AppKonto'; Kat = 'Berechtigung'; Titel = 'Apps sehen keine Kontoinformationen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O P107, P036'
           Text = 'Apps dürfen Name, Bild und Kontodaten nicht lesen.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\userAccountInformation'; Name = 'Value'; Wert = 'Deny'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\userAccountInformation'; Name = 'Value'; Wert = 'Deny'; Typ = 'String' }
           ) }
        @{ Id = 'AppDiagnose'; Kat = 'Berechtigung'; Titel = 'Apps sehen keine Diagnoseinformationen anderer Apps'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O P033, P023'
           Text = 'Apps dürfen keine Diagnosedaten anderer Apps lesen.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics'; Name = 'Value'; Wert = 'Deny'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\appDiagnostics'; Name = 'Value'; Wert = 'Deny'; Typ = 'String' }
           ) }
        @{ Id = 'AppStandort'; Kat = 'Berechtigung'; Titel = 'Apps dürfen den Standort nicht abfragen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O P057'
           Text = 'Gilt für alle Benutzer dieses PCs.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'; Name = 'Value'; Wert = 'Deny'; Typ = 'String' } ) }
        @{ Id = 'AppBewegung'; Kat = 'Berechtigung'; Titel = 'Apps sehen keine Bewegungsdaten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Registry, O&O P048, P049'
           Text = 'Apps dürfen Bewegungs- und Aktivitätsdaten nicht lesen.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\activity'; Name = 'Value'; Wert = 'Deny'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\activity'; Name = 'Value'; Wert = 'Deny'; Typ = 'String' }
           ) }
        @{ Id = 'AppStarts'; Kat = 'Berechtigung'; Titel = 'Programmstarts und zuletzt geöffnete Dateien nicht verfolgen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O P025, M011'
           Text = 'Windows merkt sich keine Programmstarts für das Startmenü und zeigt keine zuletzt geöffneten Elemente in Sprunglisten.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackProgs'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_TrackDocs'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Synchronisierung'; Kat = 'Berechtigung'; Titel = 'Einstellungen nicht mit dem Microsoft-Konto synchronisieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O Y001 bis Y007'
           Text = 'Keine Synchronisierung von Design, Browser, Kennwörtern, Sprache, Barrierefreiheit und weiteren Einstellungen.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'; Name = 'DisableSettingSync'; Wert = 2; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'; Name = 'DisableSettingSyncUserOverride'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'; Name = 'DisableDesktopThemeSettingSync'; Wert = 2; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'; Name = 'DisableWebBrowserSettingSync'; Wert = 2; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'; Name = 'DisableCredentialsSettingSync'; Wert = 2; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'; Name = 'DisableLanguageSettingSync'; Wert = 2; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'; Name = 'DisableAccessibilitySettingSync'; Wert = 2; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'; Name = 'DisableWindowsSettingSync'; Wert = 2; Typ = 'DWord' }
           ) }
        @{ Id = 'HintergrundApps'; Kat = 'Berechtigung'; Titel = 'Store-Apps nicht im Hintergrund ausführen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Bedingung = 'Win10'
           Quelle = 'Sophia BackgroundUWPApps (Windows 10)'
           Text = 'Store-Apps laufen nur noch, wenn sie geöffnet sind.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Wert = 1; Typ = 'DWord' } ) }
        # ------------------------------------------------------------------ Dienste und geplante Aufgaben
        @{ Id = 'DiensteSelten'; Kat = 'Hintergrund'; Titel = 'Selten gebrauchte Dienste deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Dienste'
           Text = 'Fax, Händlerdemo, Kartenverwaltung, Wallet und Zahlungen, räumliche Daten, Mixed Reality, Jugendschutz, Insider, Mobilfunkzeit, SMS-Router, Telefon und Nachrichten werden beendet und deaktiviert.'
           Aktionen = @(
               @{ Art = 'Dienst'; Name = 'Fax'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'RetailDemo'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'MapsBroker'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'WalletService'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'SEMgrSvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'SharedRealitySvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'MixedRealityOpenXRSvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'WpcMonSvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'wisvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'autotimesvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'SmsRouter'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'PhoneSvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'MessagingService'; Start = 'Disabled' }
           ) }
        @{ Id = 'DiensteSync'; Kat = 'Hintergrund'; Titel = 'Synchronisierung von Kontakten, Mails und Kalender deaktivieren'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'MSE'
           Quelle = 'Pack Dienste'
           Text = 'Die Dienste OneSyncSvc, PimIndexMaintenanceSvc und UnistoreSvc werden deaktiviert.'
           Hinweis = 'Die Apps Mail, Kalender und Kontakte synchronisieren danach nicht mehr; Outlook ist nicht betroffen.'
           Aktionen = @(
               @{ Art = 'Dienst'; Name = 'OneSyncSvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'PimIndexMaintenanceSvc'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'UnistoreSvc'; Start = 'Disabled' }
           ) }
        @{ Id = 'DiensteHotspot'; Kat = 'Hintergrund'; Titel = 'Internetverbindungsfreigabe und mobilen Hotspot deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Dienste'
           Text = 'Die Dienste SharedAccess und icssvc werden deaktiviert.'
           Hinweis = 'Mobiler Hotspot und Internetfreigabe funktionieren danach nicht mehr; manche VM-Netzwerke nutzen SharedAccess.'
           Aktionen = @(
               @{ Art = 'Dienst'; Name = 'SharedAccess'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'icssvc'; Start = 'Disabled' }
           ) }
        @{ Id = 'DiensteSmartcard'; Kat = 'Hintergrund'; Titel = 'Smartcard-Dienste deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'Pack Dienste'
           Text = 'Die Dienste SCardSvr und ScDeviceEnum werden deaktiviert.'
           Hinweis = 'Anmeldung mit Smartcard, Dienstausweis oder Kartenleser funktioniert danach nicht mehr.'
           Aktionen = @(
               @{ Art = 'Dienst'; Name = 'SCardSvr'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'ScDeviceEnum'; Start = 'Disabled' }
           ) }
        @{ Id = 'DiensteTablet'; Kat = 'Hintergrund'; Titel = 'Dienst für Bildschirmtastatur und Handschrift deaktivieren'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'MSE'; Bedingung = 'Desktop'
           Quelle = 'Pack Dienste'
           Text = 'Der Dienst TabletInputService wird deaktiviert (nur auf Desktop-PCs ohne Touchscreen sinnvoll).'
           Hinweis = 'Auf Notebooks mit Touchscreen oder Stift fehlen danach Bildschirmtastatur, Emoji-Feld und Handschrift.'
           Aktionen = @( @{ Art = 'Dienst'; Name = 'TabletInputService'; Start = 'Disabled' } ) }
        @{ Id = 'DiensteSicherung'; Kat = 'Hintergrund'; Titel = 'Dienst Windows-Sicherung deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Dienste'
           Text = 'Der Dienst SDRSVC (Sichern und Wiederherstellen, Windows 7) wird deaktiviert.'
           Hinweis = 'Nur weglassen, wenn dieser PC mit "Sichern und Wiederherstellen (Windows 7)" gesichert wird. Wiederherstellungspunkte sind nicht betroffen.'
           Aktionen = @( @{ Art = 'Dienst'; Name = 'SDRSVC'; Start = 'Disabled' } ) }
        @{ Id = 'DiensteEdgeUpdate'; Kat = 'Update'; Titel = 'Edge-Updatedienste deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'Pack Dienste'
           Text = 'Die Dienste edgeupdate, edgeupdatem und MicrosoftEdgeElevationService werden deaktiviert.'
           Hinweis = 'Edge aktualisiert sich danach nur noch über Windows Update oder von Hand. Sicherheitsupdates kommen dadurch später.'
           Aktionen = @(
               @{ Art = 'Dienst'; Name = 'edgeupdate'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'edgeupdatem'; Start = 'Disabled' }
               @{ Art = 'Dienst'; Name = 'MicrosoftEdgeElevationService'; Start = 'Disabled' }
           ) }
        @{ Id = 'AufgabenTelemetrie'; Kat = 'Hintergrund'; Titel = 'Telemetrie-Aufgaben deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Aufgaben, Sophia ScheduledTasks'
           Text = 'Kompatibilitätsprüfung (Appraiser, ProgramDataUpdater, StartupAppTask), Programm zur Verbesserung der Benutzerfreundlichkeit, Proxy, USB-Telemetrie, Datenträgerdiagnose und Feedback-Aufgaben (DmClient).'
           Aktionen = @(
               @{ Art = 'Aufgabe'; Pfad = '\Microsoft\Windows\Application Experience\'; Name = 'Microsoft Compatibility Appraiser' }
               @{ Art = 'Aufgabe'; Pfad = '\Microsoft\Windows\Application Experience\'; Name = 'ProgramDataUpdater' }
               @{ Art = 'Aufgabe'; Pfad = '\Microsoft\Windows\Application Experience\'; Name = 'StartupAppTask' }
               @{ Art = 'Aufgabe'; Pfad = '\Microsoft\Windows\Customer Experience Improvement Program\'; Name = '*' }
               @{ Art = 'Aufgabe'; Name = 'Proxy' }
               @{ Art = 'Aufgabe'; Name = 'UsbCeip' }
               @{ Art = 'Aufgabe'; Name = 'Microsoft-Windows-DiskDiagnosticDataCollector' }
               @{ Art = 'Aufgabe'; Name = 'DmClient' }
               @{ Art = 'Aufgabe'; Name = 'DmClientOnScenarioDownload' }
           ) }
        @{ Id = 'AufgabenKarten'; Kat = 'Hintergrund'; Titel = 'Aufgaben der Karten-App deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Aufgaben'
           Text = 'MapsToastTask und MapsUpdateTask.'
           Aktionen = @( @{ Art = 'Aufgabe'; Name = 'MapsToastTask' }, @{ Art = 'Aufgabe'; Name = 'MapsUpdateTask' } ) }
        @{ Id = 'AufgabenJugendschutz'; Kat = 'Hintergrund'; Titel = 'Aufgaben des Jugendschutzes deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Aufgaben'
           Text = 'FamilySafetyMonitor und FamilySafetyRefreshTask.'
           Hinweis = 'Nicht auf PCs mit Microsoft-Family-Jugendschutz.'
           Aktionen = @( @{ Art = 'Aufgabe'; Name = 'FamilySafetyMonitor' }, @{ Art = 'Aufgabe'; Name = 'FamilySafetyRefreshTask' } ) }
        @{ Id = 'AufgabenXbox'; Kat = 'Hintergrund'; Titel = 'Abgleich der Xbox-Spielstände deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Aufgaben'
           Text = 'XblGameSaveTask.'
           Hinweis = 'Spiele mit Xbox-Cloudspeicher gleichen ihre Spielstände dann nur noch beim Spielen ab.'
           Aktionen = @( @{ Art = 'Aufgabe'; Name = 'XblGameSaveTask' } ) }
        @{ Id = 'AufgabenGesicht'; Kat = 'Hintergrund'; Titel = 'Aufräumaufgabe der Gesichtserkennung deaktivieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Pack Aufgaben'
           Text = 'FODCleanupTask.'
           Aktionen = @( @{ Art = 'Aufgabe'; Name = 'FODCleanupTask' } ) }
        @{ Id = 'WartungsaufgabenNeu'; Kat = 'Hintergrund'; Titel = 'Regelmäßige Bereinigung als geplante Aufgaben einrichten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia CleanupTask, SoftwareDistributionTask, TempTask'
           Text = 'Drei Aufgaben unter \Leos Minibench: Datenträgerbereinigung alle 30 Tage, Update-Downloads alle 90 Tage, temporäre Dateien älter als einen Tag alle 60 Tage. Ohne Skriptdateien, nur Windows-Befehle.'
           Hinweis = 'Bleibt bewusst auf dem PC; Rückgängig auf der Seite Änderungen entfernt die Aufgaben.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'Wartungsaufgaben' } ) }
        # ------------------------------------------------------------------ Windows-Funktionen und Zusatzfeatures
        @{ Id = 'FeaturePowerShell2'; Kat = 'Funktionen'; Titel = 'PowerShell 2.0 abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Features'
           Text = 'Die veraltete PowerShell 2.0 lässt sich für Angriffe ohne Protokollierung missbrauchen; aktuelle PowerShell bleibt.'
           Aktionen = @( @{ Art = 'Feature'; Name = 'MicrosoftWindowsPowerShellV2Root' }, @{ Art = 'Feature'; Name = 'MicrosoftWindowsPowerShellV2' } ) }
        @{ Id = 'FeatureRecall'; Kat = 'Funktionen'; Titel = 'Windows-Funktion Recall abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Features'
           Text = 'Nur auf Copilot+-PCs vorhanden.'
           Aktionen = @( @{ Art = 'Feature'; Name = 'Recall' } ) }
        @{ Id = 'FeatureTftpTelnet'; Kat = 'Funktionen'; Titel = 'TFTP- und Telnet-Client abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Features'
           Text = 'Unverschlüsselte Altprotokolle.'
           Aktionen = @( @{ Art = 'Feature'; Name = 'TFTP' }, @{ Art = 'Feature'; Name = 'TelnetClient' } ) }
        @{ Id = 'FeatureXps'; Kat = 'Funktionen'; Titel = 'XPS-Druckdienste abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Features'
           Text = 'Der XPS-Dokumentdrucker verschwindet.'
           Aktionen = @( @{ Art = 'Feature'; Name = 'Printing-XPSServices-Features' } ) }
        @{ Id = 'FeatureArbeitsordner'; Kat = 'Funktionen'; Titel = 'Arbeitsordner-Client abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1; Verwaltet = $true
           Quelle = 'Pack Features'
           Text = 'Arbeitsordner (Work Folders) synchronisieren Dateien mit einem Firmenserver.'
           Aktionen = @( @{ Art = 'Feature'; Name = 'WorkFolders-Client' } ) }
        @{ Id = 'FeatureSmbDirect'; Kat = 'Funktionen'; Titel = 'SMB Direct abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Features'
           Text = 'SMB über RDMA-Netzwerkkarten, auf Arbeitsplatz-PCs praktisch nie genutzt.'
           Aktionen = @( @{ Art = 'Feature'; Name = 'SmbDirect' } ) }
        @{ Id = 'FeatureWcf'; Kat = 'Funktionen'; Titel = 'WCF-TCP-Portfreigabe abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Features'
           Text = 'Teil von .NET 4 für Serverdienste.'
           Aktionen = @( @{ Art = 'Feature'; Name = 'WCF-TCP-PortSharing45' } ) }
        @{ Id = 'FeatureMsrdc'; Kat = 'Funktionen'; Titel = 'Remotedesktop-Infrastruktur (MSRDC) abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1; Verwaltet = $true
           Quelle = 'Pack Features'
           Text = 'Grundlage für Remote-Apps und Windows-Subsystem-Funktionen.'
           Hinweis = 'WSL-Grafik (WSLg) und manche Remote-App-Lösungen brauchen MSRDC.'
           Aktionen = @( @{ Art = 'Feature'; Name = 'MSRDC-Infrastructure' } ) }
        @{ Id = 'CapSchrittaufzeichnung'; Kat = 'Funktionen'; Titel = 'Schrittaufzeichnung entfernen'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Zusatzfeatures'
           Text = 'Zusatzfeature App.StepsRecorder; Microsoft stellt es ohnehin ein.'
           Aktionen = @( @{ Art = 'Capability'; Muster = 'App.StepsRecorder*' } ) }
        @{ Id = 'CapQuickAssist'; Kat = 'Funktionen'; Titel = 'Remotehilfe (Quick Assist, alt) entfernen'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Zusatzfeatures'
           Text = 'Zusatzfeature App.Support.QuickAssist; die neue Remotehilfe kommt aus dem Store.'
           Aktionen = @( @{ Art = 'Capability'; Muster = 'App.Support.QuickAssist*' } ) }
        @{ Id = 'CapInternetExplorer'; Kat = 'Funktionen'; Titel = 'Internet Explorer entfernen'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1; Verwaltet = $true
           Quelle = 'Pack Zusatzfeatures'
           Text = 'Zusatzfeature Browser.InternetExplorer (unter Windows 10).'
           Hinweis = 'Der IE-Modus von Edge braucht ihn; in Verwaltungen mit alten Fachanwendungen weglassen.'
           Aktionen = @( @{ Art = 'Capability'; Muster = 'Browser.InternetExplore*' } ) }
        @{ Id = 'CapGesicht'; Kat = 'Funktionen'; Titel = 'Windows Hello Gesichtserkennung entfernen'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Vorlagen = ''; Minuten = 1
           Quelle = 'Pack Zusatzfeatures'
           Text = 'Zusatzfeature Hello.Face.'
           Hinweis = 'Abweichend vom Pack in keiner Vorlage: Danach ist keine Anmeldung per Gesicht (Infrarotkamera) mehr möglich.'
           Aktionen = @( @{ Art = 'Capability'; Muster = 'Hello.Face*' } ) }
        @{ Id = 'CapMathe'; Kat = 'Funktionen'; Titel = 'Mathematik-Eingabe entfernen'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Zusatzfeatures'
           Text = 'Zusatzfeature MathRecognizer (Formeleingabe per Stift).'
           Aktionen = @( @{ Art = 'Capability'; Muster = 'MathRecognizer*' } ) }
        @{ Id = 'CapIse'; Kat = 'Funktionen'; Titel = 'PowerShell ISE entfernen'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Pack Zusatzfeatures'
           Text = 'Zusatzfeature Microsoft.Windows.PowerShell.ISE; PowerShell selbst bleibt.'
           Aktionen = @( @{ Art = 'Capability'; Muster = 'Microsoft.Windows.PowerShell.ISE*' } ) }
        @{ Id = 'CapOpenSsh'; Kat = 'Funktionen'; Titel = 'OpenSSH entfernen'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1; Verwaltet = $true
           Quelle = 'Pack Zusatzfeatures'
           Text = 'Zusatzfeatures OpenSSH.Client und OpenSSH.Server.'
           Hinweis = 'Danach gibt es kein ssh und scp mehr in der Eingabeaufforderung.'
           Aktionen = @( @{ Art = 'Capability'; Muster = 'OpenSSH*' } ) }
        @{ Id = 'CapHandschrift'; Kat = 'Funktionen'; Titel = 'Handschrifterkennung entfernen'; Risiko = 'Eingriff'; Neustart = 'moeglich'; Vorlagen = 'E'; Minuten = 1; Bedingung = 'Desktop'
           Quelle = 'Pack Zusatzfeatures'
           Text = 'Sprachpakete Language.Handwriting (nur auf Desktop-PCs ohne Stift sinnvoll).'
           Aktionen = @( @{ Art = 'Capability'; Muster = 'Language.Handwriting*' } ) }
        # ------------------------------------------------------------------ Vorinstallierte Apps entfernen
        @{ Id = 'AppNachrichtenWetter'; Kat = 'Apps'; Titel = 'Nachrichten und Wetter'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.BingNews und Microsoft.BingWeather für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.BingNews' }, @{ Art = 'App'; Muster = 'Microsoft.BingWeather' } ) }
        @{ Id = 'AppHilfeTipps'; Kat = 'Apps'; Titel = 'Hilfe anfordern und Tipps'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.GetHelp und Microsoft.Getstarted für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.GetHelp' }, @{ Art = 'App'; Muster = 'Microsoft.Getstarted' } ) }
        @{ Id = 'AppSolitaer'; Kat = 'Apps'; Titel = 'Solitaire Collection'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.MicrosoftSolitaireCollection für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.MicrosoftSolitaireCollection' } ) }
        @{ Id = 'AppOfficeHub'; Kat = 'Apps'; Titel = 'Microsoft 365 (Office-Hub)'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.MicrosoftOfficeHub, die Startseite für Office im Store; installiertes Office bleibt.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.MicrosoftOfficeHub' } ) }
        @{ Id = 'AppFeedbackHub'; Kat = 'Apps'; Titel = 'Feedback-Hub'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.WindowsFeedbackHub für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.WindowsFeedbackHub' } ) }
        @{ Id = 'AppKarten'; Kat = 'Apps'; Titel = 'Karten'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.WindowsMaps für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.WindowsMaps' } ) }
        @{ Id = 'AppFilme'; Kat = 'Apps'; Titel = 'Filme & TV'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.ZuneVideo für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.ZuneVideo' } ) }
        @{ Id = 'AppMediaPlayer'; Kat = 'Apps'; Titel = 'Medienwiedergabe (Media Player, neu)'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = ''; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.ZuneMusic, unter Windows 11 die Standard-App für Musik und Videos.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.ZuneMusic' } ) }
        @{ Id = 'AppClipchamp'; Kat = 'Apps'; Titel = 'Clipchamp'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Clipchamp.Clipchamp für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Clipchamp.Clipchamp' } ) }
        @{ Id = 'AppTeamsPrivat'; Kat = 'Apps'; Titel = 'Teams (privat, Chat in der Taskleiste)'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'MicrosoftTeams, die private Teams-App von Windows 11. Teams für Arbeit oder Schule (MSTeams) bleibt.'
           Aktionen = @( @{ Art = 'App'; Muster = 'MicrosoftTeams' } ) }
        @{ Id = 'AppSmartphoneLink'; Kat = 'Apps'; Titel = 'Smartphone-Link'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.YourPhone für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.YourPhone' } ) }
        @{ Id = 'AppCortana'; Kat = 'Apps'; Titel = 'Cortana-App'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.549981C3F5F10 für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.549981C3F5F10' } ) }
        @{ Id = 'AppCopilot'; Kat = 'Apps'; Titel = 'Copilot-App'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia WindowsAI'
           Text = 'Microsoft.Copilot für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.Copilot' } ) }
        @{ Id = 'AppPowerAutomate'; Kat = 'Apps'; Titel = 'Power Automate'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.PowerAutomateDesktop für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.PowerAutomateDesktop' } ) }
        @{ Id = 'AppDevHome'; Kat = 'Apps'; Titel = 'Dev Home'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.Windows.DevHome für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.Windows.DevHome' } ) }
        @{ Id = 'AppAltlasten'; Kat = 'Apps'; Titel = 'Mixed Reality, Skype, 3D-Viewer, Wallet'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'E'; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Alte Beigaben von Windows 10: Microsoft.MixedReality.Portal, Microsoft.SkypeApp, Microsoft.Microsoft3DViewer, Microsoft.Wallet.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.MixedReality.Portal' }, @{ Art = 'App'; Muster = 'Microsoft.SkypeApp' }, @{ Art = 'App'; Muster = 'Microsoft.Microsoft3DViewer' }, @{ Art = 'App'; Muster = 'Microsoft.Wallet' } ) }
        @{ Id = 'AppKontakteAufgaben'; Kat = 'Apps'; Titel = 'Kontakte und To Do'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = ''; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Microsoft.People und Microsoft.Todos für alle Benutzer.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.People' }, @{ Art = 'App'; Muster = 'Microsoft.Todos' } ) }
        @{ Id = 'AppOutlookNeu'; Kat = 'Apps'; Titel = 'Outlook (neu)'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = ''; Minuten = 1; Verwaltet = $true
           Quelle = 'Sophia UnpinTaskbarShortcuts Outlook'
           Text = 'Microsoft.OutlookForWindows; das klassische Outlook aus Office bleibt.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.OutlookForWindows' } ) }
        @{ Id = 'AppXbox'; Kat = 'Apps'; Titel = 'Xbox-Apps und Spieleleiste'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = ''; Minuten = 1
           Quelle = 'Sophia Uninstall-UWPApps'
           Text = 'Xbox, Game Bar, Xbox Identity Provider, Sprach-Overlay und TCUI für alle Benutzer.'
           Hinweis = 'Spiele aus dem Microsoft Store und dem Game Pass brauchen den Xbox Identity Provider.'
           Aktionen = @( @{ Art = 'App'; Muster = 'Microsoft.GamingApp' }, @{ Art = 'App'; Muster = 'Microsoft.XboxApp' }, @{ Art = 'App'; Muster = 'Microsoft.XboxGamingOverlay' }, @{ Art = 'App'; Muster = 'Microsoft.XboxSpeechToTextOverlay' }, @{ Art = 'App'; Muster = 'Microsoft.Xbox.TCUI' }, @{ Art = 'App'; Muster = 'Microsoft.XboxIdentityProvider' } ) }
        # ------------------------------------------------------------------ Explorer, Taskleiste und Start
        @{ Id = 'Dateiendungen'; Kat = 'Bedienung'; Titel = 'Dateiendungen anzeigen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia FileExtensions'
           Text = 'Der Explorer zeigt Endungen wie .pdf und .exe; schützt vor getarnten Dateien.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'VersteckteDateien'; Kat = 'Bedienung'; Titel = 'Versteckte Dateien anzeigen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia HiddenItems'
           Text = 'Versteckte Dateien, Ordner und Laufwerke werden angezeigt.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Hidden'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'ExplorerDetails'; Kat = 'Bedienung'; Titel = 'Explorer: Konflikte, Kontrollkästchen, kompakte Ansicht'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia MergeConflicts, CheckBoxes, FileExplorerCompactMode'
           Text = 'Ordnerkonflikte beim Zusammenführen anzeigen, keine Kontrollkästchen zur Auswahl, keine kompakte Ansicht.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideMergeConflicts'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'AutoCheckSelect'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'UseCompactMode'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Kopierdialog'; Kat = 'Bedienung'; Titel = 'Kopierdialog mit Details, Rückfrage beim Löschen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia FileTransferDialog, RecycleBinDeleteConfirmation'
           Text = 'Der Dialog beim Kopieren zeigt Geschwindigkeit und Restzeit; vor dem Verschieben in den Papierkorb kommt eine Rückfrage.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager'; Name = 'EnthusiastMode'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'ConfirmFileDelete'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'Schnellzugriff'; Kat = 'Bedienung'; Titel = 'Schnellzugriff ohne zuletzt verwendete Dateien und Ordner'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia QuickAccessRecentFiles, QuickAccessFrequentFolders'
           Text = 'Der Schnellzugriff zeigt nur noch angeheftete Ordner.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'ShowRecent'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'ShowFrequent'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'TaskleisteSuche'; Kat = 'Bedienung'; Titel = 'Taskleiste ohne Suchfeld, Aktivitätsansicht und Personen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'Sophia TaskbarSearch, TaskViewButton, O&O M016, M015'
           Text = 'Suchfeld, Schaltfläche Aktivitätsansicht und Personen verschwinden aus der Taskleiste; die Suche bleibt über die Windows-Taste.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; Name = 'SearchboxTaskbarMode'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowTaskViewButton'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People'; Name = 'PeopleBand'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Widgets'; Kat = 'Bedienung'; Titel = 'Widgets sowie Neuigkeiten und interessante Themen aus'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'MSE'
           Quelle = 'Sophia TaskbarWidgets, NewsInterests, O&O M019'
           Text = 'Kein Widgets-Feld (Windows 11) und keine Neuigkeiten in der Taskleiste (Windows 10).'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; Name = 'AllowNewsAndInterests'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds'; Name = 'EnableFeeds'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'JetztBesprechen'; Kat = 'Bedienung'; Titel = 'Schaltfläche Jetzt besprechen ausblenden'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Bedingung = 'Win10'
           Quelle = 'Sophia MeetNow, O&O M017, M018'
           Text = 'Entfernt "Jetzt besprechen" (Skype) aus dem Infobereich.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'HideSCAMeetNow'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name = 'HideSCAMeetNow'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'TaskleisteGruppieren'; Kat = 'Bedienung'; Titel = 'Taskleiste: immer gruppieren, Task beenden per Rechtsklick'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia TaskbarCombine, TaskbarEndTask'
           Text = 'Schaltflächen eines Programms werden zusammengefasst; ein Rechtsklick bietet "Task beenden" (Windows 11).'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarGlomLevel'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'; Name = 'TaskbarEndTask'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'StartmenueAufraeumen'; Kat = 'Bedienung'; Titel = 'Startmenü ohne Empfehlungen und Kontohinweise'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Bedingung = 'Win11'
           Quelle = 'Sophia RecentlyAddedStartApps, MostUsedStartApps, StartRecommendedSection, StartRecommendationsTips, StartAccountNotifications'
           Text = 'Keine zuletzt hinzugefügten und meistverwendeten Apps, kein Bereich Empfohlen (nicht in Home), keine Tipps und keine Hinweise zum Microsoft-Konto.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name = 'HideRecentlyAddedApps'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Start'; Name = 'ShowFrequentList'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name = 'HideRecommendedSection'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_IrisRecommendations'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'Start_AccountNotifications'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'StartListe'; Kat = 'Bedienung'; Titel = 'Alle Apps im Startmenü als Liste'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Bedingung = 'Win11'
           Quelle = 'Sophia StartAppsView'
           Text = 'Die Ansicht "Alle" zeigt eine Liste statt Kategorien.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Start'; Name = 'AllAppsViewMode'; Wert = 2; Typ = 'DWord' } ) }
        @{ Id = 'Fensterschuetteln'; Kat = 'Bedienung'; Titel = 'Fenster schütteln minimiert alle anderen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia AeroShaking'
           Text = 'Titelleiste greifen und schütteln minimiert alle übrigen Fenster.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'DisallowShaking'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'Systemsteuerung'; Kat = 'Bedienung'; Titel = 'Systemsteuerung nach Kategorien'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia ControlPanelView'
           Text = 'Die Systemsteuerung öffnet in der Kategorieansicht.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel'; Name = 'AllItemsIconView'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel'; Name = 'StartupPage'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'Verknuepfungsname'; Kat = 'Bedienung'; Titel = 'Neue Verknüpfungen ohne Zusatz "- Verknüpfung"'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia ShortcutsSuffix'
           Text = 'Neue Verknüpfungen heißen wie das Ziel.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates'; Name = 'ShortcutNameTemplate'; Wert = '%s.lnk'; Typ = 'String' } ) }
        @{ Id = 'DruckTaste'; Kat = 'Bedienung'; Titel = 'Druck-Taste öffnet das Ausschneidetool'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia PrtScnSnippingTool'
           Text = 'Die Taste Druck startet die Bildschirmausschnitt-Auswahl.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Keyboard'; Name = 'PrintScreenKeyForSnippingEnabled'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'Tastatur'; Kat = 'Bedienung'; Titel = 'Num-Taste beim Start an, keine Einrastfunktion per Umschalt'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia NumLock, StickyShift'
           Text = 'Die Num-Taste ist auf dem Anmeldebildschirm an; fünfmal Umschalt öffnet nicht mehr die Einrastfunktion.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard'; Name = 'InitialKeyboardIndicators'; Wert = '2147483650'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Accessibility\StickyKeys'; Name = 'Flags'; Wert = '506'; Typ = 'String' }
           ) }
        @{ Id = 'AutoPlay'; Kat = 'Bedienung'; Titel = 'Automatische Wiedergabe aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia Autoplay'
           Text = 'Beim Anschließen von USB-Sticks und Datenträgern startet nichts von selbst.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers'; Name = 'DisableAutoplay'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'F1Hilfe'; Kat = 'Bedienung'; Titel = 'F1 öffnet keine Hilfe im Browser'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia F1HelpPage'
           Text = 'Die Taste F1 auf dem Desktop und im Explorer startet keine Bing-Suche mehr.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Classes\Typelib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}\1.0\0\win64'; Name = '(default)'; Wert = ''; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Classes\Typelib\{8cec5860-07a1-11d9-b15e-000d56bfe6ee}\1.0\0\win32'; Name = '(default)'; Wert = ''; Typ = 'String' }
           ) }
        @{ Id = 'StandardDrucker'; Kat = 'Bedienung'; Titel = 'Windows wechselt den Standarddrucker nicht selbst'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia WindowsManageDefaultPrinter'
           Text = 'Der Standarddrucker bleibt, auch wenn zuletzt ein anderer genutzt wurde.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'; Name = 'LegacyDefaultPrinterMode'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'StoreOeffnenMit'; Kat = 'Bedienung'; Titel = 'Kein Store-Eintrag im Dialog Öffnen mit'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia UseStoreOpenWith'
           Text = 'Der Dialog Öffnen mit bietet nicht mehr an, eine App im Store zu suchen.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name = 'NoUseStoreOpenWith'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'KontextMsi'; Kat = 'Bedienung'; Titel = 'Kontextmenü: MSI-Pakete entpacken'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia MSIExtractContext'
           Text = 'Rechtsklick auf eine .msi-Datei bietet "Alles extrahieren" (msiexec /a in einen Ordner daneben).'
           Aktionen = @( @{ Art = 'RegKey'; Pfad = 'HKCU:\Software\Classes\Msi.Package\shell\Extract'; Werte = @(
               @{ Name = 'MUIVerb'; Wert = '@shell32.dll,-37514'; Typ = 'String' }
               @{ Name = 'Icon'; Wert = 'shell32.dll,-16817'; Typ = 'String' }
               @{ Unterschluessel = 'Command'; Name = '(default)'; Wert = 'msiexec.exe /a "%1" /qb TARGETDIR="%1 extracted"'; Typ = 'String' } ) } ) }
        @{ Id = 'KontextCab'; Kat = 'Bedienung'; Titel = 'Kontextmenü: CAB-Pakete installieren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia CABInstallContext'
           Text = 'Rechtsklick auf eine .cab-Datei bietet "Installieren" (DISM /Add-Package, mit Administratorrechten).'
           Aktionen = @( @{ Art = 'RegKey'; Pfad = 'HKCU:\Software\Classes\CABFolder\Shell\RunAs'; Werte = @(
               @{ Name = 'MUIVerb'; Wert = '@shell32.dll,-10210'; Typ = 'String' }
               @{ Name = 'HasLUAShield'; Wert = ''; Typ = 'String' }
               @{ Unterschluessel = 'Command'; Name = '(default)'; Wert = 'cmd /c "DISM.exe /Online /Add-Package /PackagePath:"%1" /NoRestart & pause"'; Typ = 'String' } ) } ) }
        @{ Id = 'Terminal'; Kat = 'Bedienung'; Titel = 'Windows Terminal als Standardkonsole'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Bedingung = 'Terminal'
           Quelle = 'Sophia DefaultTerminalApp'
           Text = 'Eingabeaufforderung und PowerShell öffnen im Windows Terminal (nur wenn es installiert ist).'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Console\%%Startup'; Name = 'DelegationConsole'; Wert = '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Console\%%Startup'; Name = 'DelegationTerminal'; Wert = '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'; Typ = 'String' }
           ) }
        @{ Id = 'Win10Explorer'; Kat = 'Bedienung'; Titel = 'Windows 10: Menüband offen, Cortana-Schaltfläche und Ink-Arbeitsbereich aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Bedingung = 'Win10'
           Quelle = 'Sophia FileExplorerRibbon, CortanaButton, WindowsInkWorkspace, SecondsInSystemClock, NotificationAreaIcons'
           Text = 'Menüband im Explorer ausgeklappt, keine Cortana-Schaltfläche, kein Windows-Ink-Arbeitsbereich, Uhr ohne Sekunden, selten genutzte Symbole im Infobereich ausgeblendet.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Ribbon'; Name = 'MinimizedStateTabletModeOff'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowCortanaButton'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PenWorkspace'; Name = 'PenWorkspaceButtonDesiredVisibility'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'ShowSecondsInSystemClock'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'; Name = 'EnableAutoTray'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'LangePfade'; Kat = 'Bedienung'; Titel = 'Pfade über 260 Zeichen erlauben'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'SE'
           Quelle = 'Sophia Win32LongPathLimit (Windows 10)'
           Text = 'Programme, die es unterstützen, dürfen lange Pfade nutzen (LongPathsEnabled).'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'; Name = 'LongPathsEnabled'; Wert = 1; Typ = 'DWord' } ) }
        # ------------------------------------------------------------------ Darstellung und persönliche Vorlieben
        @{ Id = 'DunklerModus'; Kat = 'Darstellung'; Titel = 'Dunkler Modus für Windows und Apps'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'E'
           Quelle = 'Sophia WindowsColorMode, AppColorMode'
           Text = 'Taskleiste, Startmenü und Apps im dunklen Design.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'SystemUsesLightTheme'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name = 'AppsUseLightTheme'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'TaskleisteLinks'; Kat = 'Darstellung'; Titel = 'Taskleiste links ausrichten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'E'; Bedingung = 'Win11'
           Quelle = 'Sophia TaskbarAlignment'
           Text = 'Startschaltfläche und Symbole links wie unter Windows 10.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'TaskbarAl'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'Andocken'; Kat = 'Darstellung'; Titel = 'Andockhilfe aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'E'; Bedingung = 'Win10'
           Quelle = 'Sophia SnapAssist (Windows 10)'
           Text = 'Nach dem Andocken eines Fensters schlägt Windows keine weiteren Fenster vor.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'SnapAssist'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'Anmeldeanimation'; Kat = 'Darstellung'; Titel = 'Keine Animation bei der ersten Anmeldung'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia FirstLogonAnimation'
           Text = 'Neue Benutzer sehen nicht "Hallo" und "Wir bereiten alles vor".'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name = 'EnableFirstLogonAnimation'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'Hintergrundqualitaet'; Kat = 'Darstellung'; Titel = 'Desktophintergrund ohne JPEG-Verlust'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia JPEGWallpapersQuality'
           Text = 'Windows komprimiert JPEG-Hintergrundbilder nicht nach (Qualität 100).'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Desktop'; Name = 'JPEGImportQuality'; Wert = 100; Typ = 'DWord' } ) }
        @{ Id = 'BildschirmfotoDesktop'; Kat = 'Darstellung'; Titel = 'Bildschirmfotos (Win+Druck) auf den Desktop'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'E'
           Quelle = 'Sophia WinPrtScrFolder'
           Text = 'Bildschirmfotos landen auf dem Desktop statt unter Bilder\Screenshots.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'; Name = '{B7BEDE81-DF94-4682-A7D8-57A52620B86F}'; Wert = '%USERPROFILE%\Desktop'; Typ = 'ExpandString' } ) }
        @{ Id = 'Laufwerksname'; Kat = 'Darstellung'; Titel = 'Systemlaufwerk "Windows" nennen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'Pack Indizierung (Label)'
           Text = 'Die Bezeichnung des Systemlaufwerks wird "Windows".'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'Laufwerksname'; Werte = 'Windows' } ) }
        # ------------------------------------------------------------------ Leistung, Spiele und Energie
        @{ Id = 'Indizierung'; Kat = 'Leistung'; Titel = 'Indizierung aller Laufwerke aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Minuten = 1
           Quelle = 'Pack Indizierung'
           Text = 'Die Windows-Suche indiziert die Inhalte der Laufwerke nicht mehr; spart Schreibvorgänge und Hintergrundlast.'
           Hinweis = 'Die Suche nach Dateiinhalten und in Outlook wird langsamer. Der Dienst Windows Search bleibt.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'Indizierung' } ) }
        @{ Id = 'Mausbeschleunigung'; Kat = 'Leistung'; Titel = 'Mausbeschleunigung aus (MarkC-Fix)'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'SE'
           Quelle = 'Pack Registry'
           Text = 'Zeigerbeschleunigung aus und lineare Kurve (MarkC, 100 % Skalierung); gilt nach der nächsten Anmeldung.'
           Hinweis = 'Abweichend vom Pack als Zeichenfolge gespeichert, wie Windows die Mauswerte selbst ablegt.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSpeed'; Wert = '0'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold1'; Wert = '0'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Mouse'; Name = 'MouseThreshold2'; Wert = '0'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Mouse'; Name = 'MouseSensitivity'; Wert = '10'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Mouse'; Name = 'MouseTrails'; Wert = '0'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Mouse'; Name = 'SmoothMouseXCurve'; Typ = 'Binary'; Wert = @(0, 0, 0, 0, 0, 0, 0, 0, 192, 204, 12, 0, 0, 0, 0, 0, 128, 153, 25, 0, 0, 0, 0, 0, 64, 102, 38, 0, 0, 0, 0, 0, 0, 51, 51, 0, 0, 0, 0, 0) }
               @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Mouse'; Name = 'SmoothMouseYCurve'; Typ = 'Binary'; Wert = @(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 56, 0, 0, 0, 0, 0, 0, 0, 112, 0, 0, 0, 0, 0, 0, 0, 168, 0, 0, 0, 0, 0, 0, 0, 224, 0, 0, 0, 0, 0) }
           ) }
        @{ Id = 'Menueverzoegerung'; Kat = 'Leistung'; Titel = 'Menüs ohne Verzögerung öffnen'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'SE'
           Quelle = 'Pack Registry'
           Text = 'Untermenüs öffnen sofort statt nach 400 ms (MenuShowDelay 0, gilt nach der nächsten Anmeldung).'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Control Panel\Desktop'; Name = 'MenuShowDelay'; Wert = '0'; Typ = 'String' } ) }
        @{ Id = 'Spieleprioritaet'; Kat = 'Leistung'; Titel = 'Spiele und Netzwerk im Multimedia-Planer bevorzugen'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'SE'
           Quelle = 'Pack Registry (Gaming)'
           Text = 'Keine Drosselung des Netzwerks bei Multimedia, keine reservierte Rechenzeit für Hintergrundaufgaben, Spiele mit hoher Priorität (CPU und Datenträger).'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Wert = 268435455; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Wert = 6; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Wert = 'High'; Typ = 'String' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Wert = 'High'; Typ = 'String' }
           ) }
        @{ Id = 'Mpo'; Kat = 'Leistung'; Titel = 'Multiplane Overlay (MPO) aus'; Risiko = 'Aendern'; Neustart = 'immer'; Vorlagen = 'SE'
           Quelle = 'Pack Registry (Gaming, OverlayTestMode)'
           Text = 'Behebt Flackern und schwarze Bildschirme mancher Grafiktreiber bei mehreren Monitoren und im randlosen Fenster.'
           Hinweis = 'Kann den Stromverbrauch bei Videowiedergabe leicht erhöhen.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm'; Name = 'OverlayTestMode'; Wert = 5; Typ = 'DWord' } ) }
        @{ Id = 'GpuPlanung'; Kat = 'Leistung'; Titel = 'Hardwarebeschleunigte GPU-Planung an'; Risiko = 'Aendern'; Neustart = 'immer'; Vorlagen = 'SE'
           Quelle = 'Sophia GPUScheduling'
           Text = 'Die Grafikkarte plant ihren Speicher selbst (HwSchMode 2); gilt nach einem Neustart und nur mit passendem Treiber.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Wert = 2; Typ = 'DWord' } ) }
        @{ Id = 'AppsNeustarten'; Kat = 'Leistung'; Titel = 'Apps nach der Anmeldung nicht neu starten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia SaveRestartableApps'
           Text = 'Windows öffnet nach Neustart und Anmeldung keine Apps von selbst wieder.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'; Name = 'RestartApps'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'Ruhezustand'; Kat = 'Leistung'; Titel = 'Ruhezustand aus (nur Desktop-PCs)'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Bedingung = 'Desktop'
           Quelle = 'Sophia Hibernation'
           Text = 'Schaltet den Ruhezustand ab und löscht hiberfil.sys (Platz in Größe des halben RAM); Schnellstart entfällt damit.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'Ruhezustand' } ) }
        @{ Id = 'Energieplan'; Kat = 'Leistung'; Titel = 'Energiesparplan Ausbalanciert'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'E'
           Quelle = 'Sophia PowerPlan'
           Text = 'Aktiviert den Plan Ausbalanciert (moderne CPUs takten damit fast genauso hoch und sparen im Leerlauf).'
           Hinweis = 'Abweichend vom Pack nur in Erweitert: Auf Spiele- und Messrechnern mit Höchstleistung bewusst weglassen; der vorige Plan steht im Änderungsprotokoll.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'Energieplan'; Werte = '381b4222-f694-41f0-9685-ff5bb260df2e' } ) }
        @{ Id = 'NetzwerkEnergie'; Kat = 'Leistung'; Titel = 'Netzwerkadapter nicht zum Energiesparen abschalten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia NetworkAdaptersSavePower'
           Text = 'Windows darf physische Netzwerkadapter nicht mehr abschalten; verhindert Verbindungsabbrüche nach dem Standby.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'NetzwerkEnergie' } ) }
        @{ Id = 'Speicheroptimierung'; Kat = 'Leistung'; Titel = 'Speicheroptimierung und Miniaturansichten-Bereinigung an'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia StorageSense, ThumbnailCacheRemoval'
           Text = 'Windows räumt temporäre Dateien selbst auf, die Datenträgerbereinigung darf den Miniaturansichten-Cache leeren.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'; Name = '01'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Thumbnail Cache'; Name = 'Autorun'; Wert = 3; Typ = 'DWord' }
           ) }
        # ------------------------------------------------------------------ Windows Update, Edge und OneDrive
        @{ Id = 'Uebermittlungsoptimierung'; Kat = 'Update'; Titel = 'Übermittlungsoptimierung aus'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Verwaltet = $true
           Quelle = 'Sophia DeliveryOptimization'
           Text = 'Updates werden nicht mehr an andere PCs im Netz oder Internet weitergegeben und nicht von ihnen bezogen.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'Registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings'; Name = 'DownloadMode'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'UpdateNeustart'; Kat = 'Update'; Titel = 'Update-Neustarts ankündigen, Nutzungszeit automatisch'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'; Verwaltet = $true
           Quelle = 'Sophia RestartNotification, ActiveHours, WindowsLatestUpdate, UpdateMicrosoftProducts, RecommendedTroubleshooting'
           Text = 'Benachrichtigung vor Neustarts, Nutzungszeit nach Gewohnheit, neueste Funktionen nicht sofort, Updates für andere Microsoft-Produkte, Problembehandlung automatisch mit Hinweis.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name = 'RestartNotificationsAllowed2'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name = 'SmartActiveHoursState'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name = 'IsContinuousInnovationOptedIn'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name = 'AllowMUUpdateService'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\WindowsMitigation'; Name = 'UserPreference'; Wert = 3; Typ = 'DWord' }
           ) }
        @{ Id = 'UpdateSofortNeustart'; Kat = 'Update'; Titel = 'Nach Updates so bald wie möglich neu starten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = ''; Verwaltet = $true
           Quelle = 'Sophia RestartDeviceAfterUpdate'
           Text = 'Windows startet für Updates neu, sobald es geht (IsExpedited).'
           Hinweis = 'Abweichend vom Pack in keiner Vorlage: Auf Arbeitsplätzen kann das mitten in der Arbeit passieren.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'; Name = 'IsExpedited'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'UpdateAufschub'; Kat = 'Update'; Titel = 'Funktionsupdates ein Jahr aufschieben'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O W004'
           Text = 'Neue Windows-Versionen kommen erst 365 Tage nach Erscheinen (nicht in Home); Sicherheitsupdates kommen weiter sofort.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'DeferFeatureUpdates'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; Name = 'DeferFeatureUpdatesPeriodInDays'; Wert = 365; Typ = 'DWord' }
           ) }
        @{ Id = 'EdgeVerknuepfung'; Kat = 'Update'; Titel = 'Edge-Updates legen keine Desktopverknüpfung an'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia PreventEdgeShortcutCreation'
           Text = 'Gilt für die Kanäle Stable, Beta, Dev und Canary.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'; Name = 'CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'; Name = 'CreateDesktopShortcut{2CD8A007-E189-409D-A2C8-9AF4EF3C72AA}'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'; Name = 'CreateDesktopShortcut{0D50BFEC-CD6A-4F9A-964C-C7416E3ACB10}'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'; Name = 'CreateDesktopShortcut{65C35B14-6C1D-4122-AC46-7148CC9D6497}'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'EdgeHintergrund'; Kat = 'Update'; Titel = 'Edge nicht im Hintergrund laden'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O E013, E014 (für den heutigen Edge umgesetzt)'
           Text = 'Kein Start-Boost und kein Weiterlaufen nach dem Schließen. Die übrigen O&O-Einträge für den alten Edge (Legacy) entfallen, weil es ihn nicht mehr gibt.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'StartupBoostEnabled'; Wert = 0; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'BackgroundModeEnabled'; Wert = 0; Typ = 'DWord' }
           ) }
        @{ Id = 'OneDriveRichtlinie'; Kat = 'Update'; Titel = 'OneDrive per Richtlinie abschalten'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O O001, O003'
           Text = 'OneDrive darf keine Dateien synchronisieren und vor der Anmeldung nicht ins Netz.'
           Hinweis = 'Wer OneDrive oder OneDrive for Business nutzt, lässt diesen Eintrag weg.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'; Name = 'DisableFileSyncNGSC'; Wert = 1; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Microsoft\OneDrive'; Name = 'PreventNetworkTrafficPreUserSignIn'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'OneDriveEntfernen'; Kat = 'Update'; Titel = 'OneDrive deinstallieren'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = 'SE'; Verwaltet = $true; Minuten = 1
           Quelle = 'Sophia OneDrive -Uninstall'
           Text = 'Beendet OneDrive und deinstalliert es für den angemeldeten Benutzer. Der Ordner OneDrive mit den Dateien bleibt.'
           Hinweis = 'Zurück: OneDrive von microsoft.com/onedrive neu installieren.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'OneDriveEntfernen' } ) }
        @{ Id = 'Speicherreserve'; Kat = 'Update'; Titel = 'Reservierten Speicher für Updates freigeben'; Risiko = 'Aendern'; Neustart = 'moeglich'; Vorlagen = 'SE'
           Quelle = 'Sophia ReservedStorage'
           Text = 'Windows hält keine rund 7 GB mehr für Updates zurück (wirkt nach dem nächsten Update).'
           Hinweis = 'Auf sehr vollen Laufwerken können große Updates dann scheitern.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'Speicherreserve' } ) }
        # ------------------------------------------------------------------ Sicherheit und Fernzugriff
        @{ Id = 'Netzwerkschutz'; Kat = 'Sicherheit'; Titel = 'Defender: Netzwerkschutz und Schutz vor unerwünschten Apps'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'SE'
           Quelle = 'Sophia NetworkProtection, PUAppsDetection'
           Text = 'Microsoft Defender blockiert Verbindungen zu bekannten Schadseiten und erkennt potenziell unerwünschte Apps (nur wenn Defender der aktive Virenschutz ist).'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'Defender'; Werte = 'EnableNetworkProtection=1;PUAProtection=1' } ) }
        @{ Id = 'DefenderMeldungen'; Kat = 'Sicherheit'; Titel = 'Defender und MRT senden keine Proben und Befallsdaten'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O S013, S014'
           Text = 'Keine automatische Übermittlung von Dateiproben und keine Befallsberichte des Tools zum Entfernen bösartiger Software.'
           Hinweis = 'Verringert den Cloudschutz für neue Schädlinge etwas.'
           Aktionen = @(
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; Name = 'SubmitSamplesConsent'; Wert = 2; Typ = 'DWord' }
               @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\MRT'; Name = 'DontReportInfectionInformation'; Wert = 1; Typ = 'DWord' }
           ) }
        @{ Id = 'KennwortAnzeigen'; Kat = 'Sicherheit'; Titel = 'Keine Schaltfläche zum Anzeigen von Kennwörtern'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'
           Quelle = 'O&O S001'
           Text = 'Kennwortfelder zeigen das Auge zum Aufdecken nicht mehr.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredUI'; Name = 'DisablePasswordReveal'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'Remoteunterstuetzung'; Kat = 'Sicherheit'; Titel = 'Remoteunterstützung nicht zulassen'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O M026'
           Text = 'Niemand kann per Einladung zur Remoteunterstützung auf diesen PC zugreifen.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'; Name = 'fAllowToGetHelp'; Wert = 0; Typ = 'DWord' } ) }
        @{ Id = 'Remotedesktop'; Kat = 'Sicherheit'; Titel = 'Remotedesktop-Verbindungen sperren'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = 'MSE'; Verwaltet = $true
           Quelle = 'O&O M027'
           Text = 'Eingehende Remotedesktop-Verbindungen werden abgelehnt (fDenyTSConnections 1).'
           Hinweis = 'In der IT-Betreuung weglassen, sonst ist der PC nicht mehr per Remotedesktop erreichbar.'
           Aktionen = @( @{ Art = 'Reg'; Pfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; Name = 'fDenyTSConnections'; Wert = 1; Typ = 'DWord' } ) }
        @{ Id = 'DnsOverHttps'; Kat = 'Sicherheit'; Titel = 'Verschlüsseltes DNS über Cloudflare (DNS over HTTPS)'; Risiko = 'Aendern'; Neustart = 'nie'; Vorlagen = ''; Verwaltet = $true; Bedingung = 'Win11'
           Quelle = 'Sophia DNSoverHTTPS (Windows 11)'
           Text = 'Aktive Netzwerkadapter nutzen 1.1.1.1 und 1.0.0.1, Windows verschlüsselt die Anfragen automatisch (EnableAutoDoh).'
           Hinweis = 'Abweichend vom Pack in keiner Vorlage: In Firmen- und Hochschulnetzen sind interne Namen danach nicht mehr auflösbar.'
            Aktionen = @( @{ Art = 'Sonder'; Name = 'DnsOverHttps'; Werte = '1.1.1.1,1.0.0.1' } ) }
        # ------------------------------------------------------------------ Grafiktreiber
        @{ Id = 'Ddu'; Kat = 'Grafik'; Titel = 'Grafiktreiber restlos entfernen (DDU, beim nächsten Neustart)'; Risiko = 'Eingriff'; Neustart = 'immer'; Vorlagen = ''; Verwaltet = $true; Minuten = 1
           Quelle = 'Pack Clean_GPU.ps1'
           Text = 'Bereitet Display Driver Uninstaller vor: Windows Update pausiert einen Tag, der nächste Start geht in den abgesicherten Modus, DDU entfernt alle Grafiktreiber und startet neu. Danach den aktuellen Treiber installieren.'
           Hinweis = 'Braucht DDU im Tools-Ordner (Werkzeuge für Optimierung holen). Mit BitLocker vorher den Wiederherstellungsschlüssel bereithalten.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'Ddu' } ) }
        @{ Id = 'NvidiaProfil'; Kat = 'Grafik'; Titel = 'NVIDIA-Profil des Optimisation Pack setzen'; Risiko = 'Eingriff'; Neustart = 'nie'; Vorlagen = ''; Bedingung = 'Nvidia'; Minuten = 1
           Quelle = 'Pack Nvidia_Settings.ps1 (NvidiaProfileInspector.nip)'
           Text = 'Setzt im Basisprofil des Treibers 15 Einstellungen (unter anderem G-SYNC aus, bevorzugte Bildwiederholrate hoch, DLSS-Voreinstellungen) mit NVIDIA Profile Inspector.'
           Hinweis = 'Braucht nvidiaProfileInspector.exe im Tools-Ordner. Zurück: NVIDIA-Systemsteuerung, 3D-Einstellungen, Wiederherstellen.'
           Aktionen = @( @{ Art = 'Sonder'; Name = 'NvidiaProfil' } ) }
    )
}
