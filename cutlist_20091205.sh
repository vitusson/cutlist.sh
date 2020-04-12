#!/bin/bash
# cutlist.sh
Stand="10.04.2020"


# Konfiguration
Kommentar=""                        # Standard Kommentar
ConvertUTF=1                        # Bei Problemen mit Umlauten
Zeige_fertige_Cutlist_am_Ende=1     # Moechtest Du die Rohdaten vorm Upload angezeigt bekommen
Cutlist_hochladen_Frage=1           # 0 laedt die cutlist ohne zu fragen hoch
Loeschen_der_fertigen_Cutlist=1     # Braucht man die noch wenn der Film eh schon geschnitten ist???

c_rot="\033[01;37;41m"
c_blau="\033[01;37;44m"
c_normal="\033[00m"

if [ -e ~/.cutlist.at ] ; then			  # pers. URL schon gespeichert ?
	CutListAT=$(head -n 1 ~/.cutlist.at)  # Ja -> URL auslesen
else 
	CutListAT="http://www.cutlist.at"     # Nein -> Standard URL verwenden
fi


# Funktionen
checkSystem () { # Ueberpruefe ob alle noetigen Programme installiert sind
    if ! type dialog > /dev/null 2>/dev/null ; then
	    echo -e "\nDialog ist nicht verfuegbar.\nBitte installiere es!"
	    exit 1
    fi

    if type avidemux2_gtk > /dev/null 2>/dev/null ; then 
	    avidemux="avidemux2_gtk"
    elif type avidemux2 > /dev/null 2>/dev/null ; then 
	    avidemux="avidemux2"
    else
        avidemux="avidemux"
    fi
    if ! type $avidemux > /dev/null 2>/dev/null ; then
	    echo -e "\nAvidemux ist nicht verfuegbar.\nBitte installiere es!"
	    exit 1
    fi

    if ! type curl > /dev/null 2>/dev/null ; then
	    echo -e "\nCurl ist nicht verfuegbar.\nBitte installiere es!"
	    exit 1
    fi
}

writeCutlistHeader () {					# Kopfdaten fuer die Cutlist schreiben
cat << HEADER > $2
[General]
Application=cutlist.sh
Version=$Stand
ApplyToFile=$1
OriginalFileSizeBytes=$filesize
FramesPerSecond=$FPS
IntendedCutApplication=Avidemux
IntendedCutApplicationVersion=2.6.20
IntendedCutApplicationOptions=
CutCommandLine=
NoOfCuts=$number_of_cuts
[Info]
Author=$author
RatingByAuthor=$rating
EPGError=$EPGError
ActualContent=$ActualContent
MissingBeginning=$MissingBeginning
MissingEnding=$MissingEnding
MissingAudio=$MissingAudio
MissingVideo=$MissingVideo
OtherError=$OtherError
OtherErrorDescription=$OtherErrorDescription
SuggestedMovieName=$suggest
UserComment=$comment
HEADER
}

writeCutlistSegment  () { # Schnitte in die Cutlist schreiben
    echo "[Cut" $1 "]" | tr -d " " >> $3
    start_us=$(echo $2 | cut -d"," -f2)
    duration_us=$(echo $2 | cut -d"," -f3 | cut -d")" -f1)
    echo "Start="$(         echo "$start_us/1000000"         | bc -l | sed '/\./ s/\.\{0,1\}0\{1,\}$//') >> $3
    echo "StartFrame="$(    echo "$start_us/1000000*$FPS"    | bc -l | sed '/\./ s/\.\{0,1\}0\{1,\}$//') >> $3
    echo "Duration="$(      echo "$duration_us/1000000"      | bc -l | sed '/\./ s/\.\{0,1\}0\{1,\}$//') >> $3
    echo "DurationFrames="$(echo "$duration_us/1000000*$FPS" | bc -l | sed '/\./ s/\.\{0,1\}0\{1,\}$//') >> $3 
}

showInfoDialog () { # Hinweis
    echo -e "\nstarte Avidemux ... (Vergiss nicht das Projekt zu speichern, File -> Project Script -> Save As Project!)"
}

writeAvidemuxProject () { # Schreibe Avidemux Projekt Datei
cat <<  ADMP > $2
#PY  <- Needed to identify #

adm = Avidemux()
adm.loadVideo("$1")
ADMP
}

uploadCutlist () {					# Schreibe Avidemux Projekt Datei
    if [ $ConvertUTF -eq 1 ] ; then
	    iconv -f utf-8 -t iso-8859-1 $1 --output $1.conv
	    mv $1.conv $1
    fi
    curl -F userfile[]=@"$1" -F MAX_FILE_SIZE=10000000 -F confirm=true -F type=blank -F userid=$2 -F version=1 "$CutListAT/index.php?upload=2"
    if [ $? -eq 0 ] ; then									
	    echo -e "\nErfolgreich zu Cutlist.at hochgeladen" 
    else
	    Cutlist_diesmal_nicht_loeschen=1
    fi
}

schneiden () {
    if [ `echo "$auswahl" | grep / | wc -l` -eq 0 ] ; then
	    auswahl="$PWD/$auswahl"
    fi
    if [[ "$auswahl" == *.mkv ]]; then
        auswahl2=${auswahl:0:-4}
    else
        auswahl2=$auswahl
    fi

    # Variablen bestimmen
    avidemux_project=${auswahl%.*}.py
    cutlist=$auswahl.cutlist
    filesize=$(stat -c %s "$auswahl2")
    file=$(echo "$auswahl" | rev | cut -d"/" -f1 | rev)
    cutfile=$(echo "$cutlist" | rev | cut -d"/" -f1 | rev)

    writeAvidemuxProject "$auswahl" "$avidemux_project"        # Avidemux im Hintergrund (!) starten
    showInfoDialog $1

    $avidemux --nogui --force-smart --run "$avidemux_project" --save-workbench "$avidemux_project" 1>/dev/null 2>/dev/null

    number_of_cuts=`grep -c "adm.addSegment" "$avidemux_project"`				# Wie viele Schnitte gibt es?
    if [ $number_of_cuts -eq 0 ] ; then							# Abbruch bei Null Schnitte
	    printf "$c_rot Du hast in Avidemux keine Schnitte definiert,            $c_normal\n"
	    printf "$c_rot oder vergessen diese zu speichern (File -> Save Project) $c_normal\n"
	    printf "$c_rot Dann gibt es hier leider nichts mehr zu machen :-(       $c_normal\n"
	    echo
	    rm "$avidemux_project"								# temporaere Datei loeschen
    exit 1
    fi
    
    duration=$(mkvinfo "$auswahl" | egrep -o "duration: [0-9]+\.?[0-9]*" | cut -d " " -f 2 | head -n 1)  # in ms
    FPS=$( echo "scale=10;1000/$duration" | bc -l | sed '/\./ s/\.\{0,1\}0\{1,\}$//')
    echo "FPS: $FPS.  duration: ${duration}ms"

    # Bewertungs-Dialog
    dialog --menu "Bewertung" 14 72 7 0 "[0] Dummy oder keine Cutlist" 1 "[1] Anfang und Ende grob geschnitten" 2 "[2] Anfang und Ende halbwegs genau geschnitten" 3 "[3] Schnitt ist annehmbar, Werbung entfernt" 4 "[4] doppelte Szenen nicht entfernt oder schönere Schnitte mögl." 5 "[5] Saemtliches unerwuenschtes Material framegenau entfernt" 2> .cutrating
    if [ $? -eq 1 ] ; then									# Skript_Ende bei Abbruch
	    exit 1
    fi
    rating=$(cat .cutrating)
    rm .cutrating
											    # Zustands-Dialog
    dialog --menu "Info" 14 40  7 1 "Alles in Ordnung" 2 "Falscher Inhalt / EPG-Fehler" 3 "Fehlender Anfang" 4 "Fehlendes Ende" 5 "Tonspur fehlt" 6 "Videospur fehlt" 7 "Sonstiger Fehler" 2> .cutinfo 
    if [ $? -eq 1 ] ; then									# Skript_Ende bei Abbruch
	    exit 1
    fi
    infos=$(cat .cutinfo)
    rm .cutinfo

    EPGError="0"              # Setze zunaechst einmal
    ActualContent=""          # neutrale Werte fuer
    MissingBeginning="0"      # die Cutlist
    MissingEnding="0"
    MissingAudio="0"
    MissingVideo="0"
    OtherError="0"
    OtherErrorDescription=""
    comment=""

    case $infos in            # Setze nun spezifische Werte
	    2) EPGError="1";dialog --inputbox "Tatsaechlicher Inhalt" 7 70 "Inhalt" 2> .actualcontent;ActualContent=$(cat .actualcontent);rm .actualcontent;;
	    3) MissingBeginning="1";;
	    4) MissingEnding="1";;
	    5) MissingAudio="1";;
	    6) MissingVideo="1";;
	    7) OtherError="1";dialog --inputbox "Fehler Beschreibung" 7 70 "Fehler" 2> .othererror;OtherErrorDescription=$(cat .othererror);rm .othererror;;
    esac
	# Vorschlag generieren
    # sugfile=`echo $file | rev | cut -d"-" -f2 | cut -d"." -f3 | cut -d"_" -f2,3,4,5,6,7,8,9 | rev | tr "_" " "`
	# Vorschlag abfragen
    dialog --inputbox "Vorschlag fuer den Dateinamen:" 7 70 "" 2> .sugfile
    if [ $? -eq 1 ] ; then									# kein Vorschlag bei Abbruch
	    suggest=""
    fi
    suggest=$(cat .sugfile)
    rm .sugfile

    # Kommentar abfragen
    dialog --inputbox "Kommentar" 7 70 "$Kommentar" 2> .cutkommentar
    comment=$(cat .cutkommentar)
    rm .cutkommentar

    # Nickname schon gespeichert?
    if [ ! -e ~/.kutlist.rc ] ; then
        # Nein -> Abfrage und speichern
	    dialog --inputbox "Autor (wird in /home/user/.kutlist.rc gespeichert)" 7 54 "cutlist.sh" 2> .cutautor 
	    author=$(cat .cutautor)
	    rm .cutautor
	    echo $author > ~/.kutlist.rc
	    uptime | sha1sum | tr "[:lower:]" "[:upper:]" | cut -b 1-20 >> ~/.kutlist.rc	# UserId generieren
	    userid=$(cat ~/.kutlist.rc | tail -n 1)
    else
        # Ja -> Namen auslesen
	    author=$(cat ~/.kutlist.rc | head -n 1)
	    userid=$(cat ~/.kutlist.rc | tail -n 1)
    fi

    writeCutlistHeader "$file" "$cutlist"

    offSet="0"
    cuts=`grep "adm.addSegment(0" "$avidemux_project"`
    count=0                                           # fuer die Cutlist
    while IFS= read -r cut; do                        # und schreibe
	    writeCutlistSegment $count "$cut" "$cutlist"  # die endgueltige
	    count=$(expr $count + 1)                      # Cutlist
    done <<< $cuts

    rm "$avidemux_project"                          # temporaere Datei loeschen

    if [ $Zeige_fertige_Cutlist_am_Ende -eq 1 ] ; then # Zeige fertige Cutlist
	    dialog --textbox "$cutlist" 20 70
    fi
    Cutlist_diesmal_nicht_loeschen=0                # Upload zu cutlist.at
    if [ $Cutlist_hochladen_Frage -eq 1 ] ; then
	    dialog --yesno "Soll die erstellte Cutlist zu Cutlist.at geladen werden ?" 5 61 
	    if [ $? -eq 0 ] ; then

		    uploadCutlist "$cutlist" $userid
	    else
		    Cutlist_diesmal_nicht_loeschen=1
	    fi
    else                                            # Upload-Frage = 0
	    uploadCutlist "$cutlist" $userid            # standardmäßig uploaden
    fi

    if [ $Loeschen_der_fertigen_Cutlist -eq 1 ] && [ $Cutlist_diesmal_nicht_loeschen -ne 1 ] ; then
	    rm "$cutlist"                               # Cutlist lokal loeschen
    fi
}

cutlistDFS () { # Cutlist vom Server loeschen
    userid=$(cat ~/.kutlist.rc | tail -n 1)
    cutlistdfs=$(echo $1 | rev | cut -d"=" -f1 | rev)
    wget -U "cutlist.sh/$Stand" -q -O - "$CutListAT/delete_cutlist.php?cutlistid=$cutlistdfs&userid=$userid&version=1"
    echo
}

help () {
cat << END
Aufruf:
$0 [options] files

Moegliche Optionen:

-dfs	Cutlist vom Server loeschen
        z.B.: cutlist.sh -dfs http://cutlist.at/getfile.php?id=123456
        oder  cutlist.sh -dfs 123456
-url	persöhnliche Cutlist.at URL speichern
        (-url http://www.cutlist.at/user/0123456789abcdef
        ohne letzten Schraegstrich ! )

(c) bowmore@otrforum $Stand
END
exit 1
}

# Start
while [ "$1" != "${1#-}" ] ; do     # solange der naechste parameter mit "-" anfaengt...
  case ${1#-} in
    dfs) cutlistDFS $2; exit 0;;
    url) shift;echo $1 > ~/.cutlist.at;exit 0;;
    *) help; exit 1;;
  esac
done
checkSystem 1                       # Teste das System
wahl=${@:-*}
for auswahl in "$wahl" ; do         # Für alle Parameter das Skript durchlaufen
    schneiden "$auswahl"
done
exit 0
