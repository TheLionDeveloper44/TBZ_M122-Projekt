# Author: TheLionDeveloper44
# Dieses Skript unterliegt der Lizenz, die in der LICENSE-Datei im Stammverzeichnis dieses Repositories enthalten ist.
# Ohne ausdrückliche schriftliche Genehmigung ist es untersagt, dieses Skript zu kopieren, zu modifizieren oder zu verbreiten.

from PySide6.QtCore import QThread, Signal
import installer

class ListInstalledThread(QThread):
    """Thread to list installed scoop applications without blocking UI."""
    results = Signal(list)
    failed = Signal(str)
    progress = Signal(str)

    def run(self):
        try:
            apps = installer.list_installed_apps(progress=self.progress.emit)
            self.results.emit(apps)
        except Exception as exc:  # noqa: BLE001
            self.failed.emit(str(exc))


class UninstallThread(QThread):
    """Thread to uninstall scoop applications without blocking UI."""
    progress = Signal(str)
    failed = Signal(str)
    finished_ok = Signal()

    def __init__(self, apps):
        super().__init__()
        self.apps = apps

    def run(self):
        try:
            installer.uninstall_apps(self.apps, progress=self.progress.emit)
            self.finished_ok.emit()
        except Exception as exc:  # noqa: BLE001
            self.failed.emit(str(exc))
