#!/bin/bash
# cutlist.sh
Stand="05.12.2009"

# Konfiguration
Kommentar=""						# Standard Kommentar
ConvertUTF=1						# Bei Problemen mit Umlauten
Zeige_fertige_Cutlist_am_Ende=1				# Moechtest Du die Rohdaten vorm Upload angezeigt bekommen
Cutlist_hochladen_Frage=1				# 0 laedt die cutlist ohne zu fragen hoch
Loeschen_der_fertigen_Cutlist=0				# Braucht man die noch wenn der Film eh schon geschnitten ist???
							# (Zur Not hat Cutlist.at ja eine Kopie :-))
c_rot="\033[01;37;41m"                                  # Rot
c_blau="\033[01;37;44m"                                 # Blau
c_normal="\033[00m"                                     # Standardwert, nicht aendern

if [ ! -e ~/.cutlist.at ] ; then			# pers. URL schon gespeichert ?
	CutListAT="http://www.cutlist.at"			# Nein -> Standard URL verwenden
else 
	CutListAT=$(cat ~/.cutlist.at | head -n 1)		# Ja -> URL auslesen
fi

# Funktionen
checkSystem () {					# Ueberpruefe ob alle noetigen Programme installiert sind
if ! type dialog > /dev/null 2>/dev/null ; then
	echo -e "\nDialog ist nicht verfuegbar.\nBitte installiere es!"
	exit 1
fi
if type avidemux2_gtk > /dev/null 2>/dev/null ; then 
	avidemux="avidemux2_gtk"
elif type avidemux2 > /dev/null 2>/dev/null ; then 
	avidemux="avidemux2"
else avidemux="avidemux"
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
comment1=Diese Cutlist unterliegt den Nutzungsbedingungen von cutlist.at (Stand: 14.Oktober 2008)
comment2=http://cutlist.at/terms/
ApplyToFile=$1
OriginalFileSizeBytes=$filesize
FramesPerSecond=$FPS
IntendedCutApplication=Avidemux
IntendedCutApplicationVersion=2.3.0
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
writeCutlistSegment () {				# Schnitte in die Cutlist schreiben

echo "[Cut" $1 "]" | tr -d " " >> $3
Start=$(echo $2 | cut -d"," -f2)
Duration=$(echo $2 | cut -d"," -f3 | cut -d")" -f1)		#" Geany workaround
echo "Start=" $(echo "scale=10;$Start/$FPS+$offSet/$FPS" | bc) | tr -d " " >> $3
echo "StartFrame=" $(echo "$Start+$offSet" | bc) | cut -d"." -f1 | tr -d " " >> $3
echo "Duration=" $(echo "scale=10;$Duration/$FPS" | bc) | tr -d " " >> $3
echo "DurationFrames="$(echo $Duration | cut -d"." -f1 | tr -d " ") >> $3 
}
showInfoDialog () {					# Hinweis
echo -e "\nstarte Avidemux ... (Vergiss nicht das Projekt zu speichern, File -> Save Project!)"
}
writeAvidemuxProject () {				# Schreibe Avidemux Projekt Datei
cat <<  ADMP > $2
//AD
var app = new Avidemux();
app.load("/$1");
ADMP

for part in $nextfiles ; do								# Für alle Parameter das Skript durchlaufen
	echo "app.append(\"$PWD/$part\");" >> $2
done


cat <<  ADMP >> $2
//End of script
ADMP
}
uploadCutlist () {					# Schreibe Avidemux Projekt Datei
if [ $ConvertUTF -eq 1 ] ; then
	iconv -f utf-8 -t iso-8859-1 $1 --output $1.conv
	mv $1.conv $1
fi
curl -F userfile[]=@$1 -F MAX_FILE_SIZE=10000000 -F confirm=true -F type=blank -F userid=$2 -F version=1 "$CutListAT/index.php?upload=2"
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

avidemux_project=$(echo "$auswahl" | sed 's/.avi$/.js/g' -)				# Variablen bestimmen
cutlist=$(echo "$auswahl" | sed 's/.avi$/.cutlist/g' -)
filesize=$(ls "$auswahl" -l | awk '{ print $5 }')
file=$(echo "$auswahl" | rev | cut -d"/" -f1 | rev)
cutfile=$(echo "$cutlist" | rev | cut -d"/" -f1 | rev)

writeAvidemuxProject "$auswahl" "$avidemux_project"						# Avidemux im Hintergrund (!) starten
showInfoDialog $1									

$avidemux --nogui --force-smart --run "$avidemux_project" --save-workbench "$avidemux_project" 1>/dev/null 2>/dev/null

number_of_cuts=`grep -c "app.addSegment" "$avidemux_project"`				# Wie viele Schnitte gibt es?
if [ $number_of_cuts -eq 0 ] ; then							# Abbruch bei Null Schnitte
	printf "$c_rot Du hast in Avidemux keine Schnitte definiert,            $c_normal\n"
	printf "$c_rot oder vergessen diese zu speichern (File -> Save Project) $c_normal\n"
	printf "$c_rot Dann gibt es hier leider nichts mehr zu machen :-(       $c_normal\n"
	echo
	rm "$avidemux_project"								# temporaeres Datei loeschen
exit 1
fi
if [ $(grep -c "app.video.fps1000" "$avidemux_project") -eq 1 ] ; then
	grabFPS=$(grep "app.video.fps1000" "$avidemux_project" | tr -d " " | tr ";" "=" | cut -d"=" -f2)
else
	grabFPS=$(grep "app.video.setFps1000(25000);" "$avidemux_project" | cut -d"(" -f2 | cut -d")" -f1)
fi

FPS=$(echo "$grabFPS*0.001" | bc)
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

EPGError="0"										# Setze zunaechst einmal
ActualContent=""									# neutrale Werte fuer
MissingBeginning="0"									# die Cutlist
MissingEnding="0"
MissingAudio="0"
MissingVideo="0"
OtherError="0"
OtherErrorDescription=""
comment=""

case $infos in										# Setze nun spezifische Werte
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
		
merged=`grep -c "app.append" "$avidemux_project"`
if [ $merged -ne 0 ] ; then
	mergedComment=`grep "app.append" "$avidemux_project" | rev | cut -d"/" -f1 | rev | cut -d'"' -f1 | sed -e :a -e '$!N;s/\n/;/;ta'`
	Kommentar="Merged Cutlist: Vor dem Schneiden Nachfolgesendung(en) ($mergedComment) ankleben!"
fi
											# Kommentar abfragen
dialog --inputbox "Kommentar" 7 70 "$Kommentar" 2> .cutkommentar
comment=$(cat .cutkommentar)
rm .cutkommentar

if [ ! -e ~/.kutlist.rc ] ; then							# Nickname schon gespeichert ?
	dialog --inputbox "Autor (wird in /home/user/.kutlist.rc gespeichert)" 7 54 "cutlist.sh" 2> .cutautor 
	author=$(cat .cutautor)
	rm .cutautor
	echo $author > ~/.kutlist.rc
	uptime | sha1sum | tr "[:lower:]" "[:upper:]" | cut -b 1-20 >> ~/.kutlist.rc	# UserId generieren
	userid=$(cat ~/.kutlist.rc | tail -n 1)
											# Nein -> Abfrage und speichern
else 
	author=$(cat ~/.kutlist.rc | head -n 1)						# Ja -> Namen auslesen
	userid=$(cat ~/.kutlist.rc | tail -n 1)						# Ja -> Namen auslesen
fi

writeCutlistHeader "$file" "$cutlist"							
if [ $merged -ne 0 ] ; then
	echo "MERGED=$mergedComment" >> "$cutlist"
fi

offSet="0"
cuts=`grep "app.addSegment(0" "$avidemux_project"`
count=0											# fuer die Cutlist
for cut in $cuts ; do									# und schreibe
	writeCutlistSegment $count $cut "$cutlist"						# die endgueltige
	count=$(expr $count + 1)								# Cutlist
done
if [ $merged -ne 0 ] ; then
	offSet=$(expr $(mplayer -frames 0 -identify "$auswahl" 2>/dev/null | grep ID_LENGTH | cut -d"=" -f2)*25 | bc)
	merging=1
	mergedFiles=`grep "app.append" "$avidemux_project" | rev | cut -d"/" -f1 | rev | cut -d'"' -f1`
	for mergeFile in "$mergedFiles" ; do
		echo "$mergeFile"
		cutstring="app.addSegment($merging"
		cuts=`grep $cutstring "$avidemux_project"`
		for cut in $cuts ; do									# und schreibe
			echo $cut
			writeCutlistSegment $count $cut "$cutlist"						# die endgueltige
			count=$(expr $count + 1)								# Cutlist
		done
		offSet=$(expr $offSet+$(mplayer -frames 0 -identify "$mergeFile" 2>/dev/null | grep ID_LENGTH | cut -d"=" -f2)*25 | bc)
		merging=$(expr $merging + 1)
	done
fi

rm "$avidemux_project"									# temporaeres Datei loeschen

if [ $Zeige_fertige_Cutlist_am_Ende -eq 1 ] ; then					# Zeige fertige Cutlist
	dialog --textbox "$cutlist" 20 70
fi
Cutlist_diesmal_nicht_loeschen=0											# Upload zu cutlist.at
if [ $Cutlist_hochladen_Frage -eq 1 ] ; then
	dialog --yesno "Soll die erstellte Cutlist zu Cutlist.at geladen werden ?" 5 61 
	if [ $? -eq 0 ] ; then

		uploadCutlist "$cutlist" $userid
	else
		Cutlist_diesmal_nicht_loeschen=1
	fi
else											# Upload-Frage = 0
	uploadCutlist "$cutlist" $userid							# standardmäßig uploaden
fi

if [ $Loeschen_der_fertigen_Cutlist -eq 1 ] && [ $Cutlist_diesmal_nicht_loeschen -ne 1 ] ; then
	rm "$cutlist"									# Cutlist lokal loeschen
fi
}
cutlistDFS () {						# Cutlist vom Server loeschen
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
while [ "$1" != "${1#-}" ] ; do				# solange der naechste parameter mit "-" anfaengt...
  case ${1#-} in
    dfs) cutlistDFS $2; exit 0;;
    url) shift;echo $1 > ~/.cutlist.at;exit 0;;
    *) help; exit 1;;
  esac
done
checkSystem 1						# Teste das System
wahl=${@:-*}
for auswahl in "$wahl" ; do				# Für alle Parameter das Skript durchlaufen
schneiden "$auswahl"
done
exit 0
