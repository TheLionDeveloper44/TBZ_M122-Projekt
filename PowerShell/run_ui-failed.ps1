# Author: TheLionDeveloper44
# Dieses Skript unterliegt der Lizenz, die in der LICENSE-Datei im Stammverzeichnis dieses Repositories enthalten ist.
# Ohne ausdrückliche schriftliche Genehmigung ist es untersagt, dieses Skript zu kopieren, zu modifizieren oder zu verbreiten.

# Zeige eine Fehlermeldung an, wenn das Skript nicht als Administrator ausgeführt wird.

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show("You haven't ran the run_installation.cmd Script as an Administrator. Stopping the Installation", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)