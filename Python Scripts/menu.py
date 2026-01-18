# Author: TheLionDeveloper44
# Dieses Skript unterliegt der Lizenz, die in der LICENSE-Datei im Stammverzeichnis dieses Repositories enthalten ist.
# Ohne ausdrückliche schriftliche Genehmigung ist es untersagt, dieses Skript zu kopieren, zu modifizieren oder zu verbreiten.

import sys
from PySide6.QtCore import Qt, QThread, Signal, QPropertyAnimation, QSize
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QPlainTextEdit,
    QScrollArea,
    QVBoxLayout,
    QWidget,
    QGraphicsOpacityEffect,
    QProgressBar,
    QTabWidget,
    QListWidget,
    QListWidgetItem,
)
from PySide6.QtGui import QIcon, QFont, QColor
import installer
import uninstaller


class SearchThread(QThread):
    results = Signal(list)
    failed = Signal(str)
    progress = Signal(str)

    def __init__(self, term: str):
        super().__init__()
        self.term = term

    def run(self):
        try:
            apps = installer.search_apps(self.term, progress=self.progress.emit)
            self.results.emit(apps)
        except Exception as exc:  # noqa: BLE001
            self.failed.emit(str(exc))


class InstallThread(QThread):
    progress = Signal(str)
    failed = Signal(str)
    finished_ok = Signal()

    def __init__(self, apps):
        super().__init__()
        self.apps = apps

    def run(self):
        try:
            installer.install_apps(self.apps, progress=self.progress.emit)
            self.finished_ok.emit()
        except Exception as exc:  # noqa: BLE001
            self.failed.emit(str(exc))


class MenuWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("App-Verwaltung")
        self.resize(1000, 720)
        self._checkboxes = []
        self._installed_checkboxes = []
        self._selected_apps = set()  # Track selected apps across searches
        self._installed_apps = set()  # Track installed apps to avoid reinstall
        self._fade_anim = None
        self._build_ui()
        self._apply_style()
        self._fade_in(self.centralWidget())
        # Auto-load installed apps on startup for reinstall prevention
        self._refresh_installed_list()

    def _build_ui(self):
        central = QWidget()
        main_layout = QVBoxLayout(central)
        main_layout.setSpacing(0)
        main_layout.setContentsMargins(0, 0, 0, 0)

        # Header
        header = QLabel("🚀 App-Verwaltung")
        header_font = QFont()
        header_font.setPointSize(24)
        header_font.setBold(True)
        header.setFont(header_font)
        header.setStyleSheet("padding: 20px 20px 10px 20px; color: #1f2937;")
        main_layout.addWidget(header)

        # Subtitle
        subtitle = QLabel("Verwalten Sie Ihre Scoop-Anwendungen effizient")
        subtitle_font = QFont()
        subtitle_font.setPointSize(10)
        subtitle.setFont(subtitle_font)
        subtitle.setStyleSheet("padding: 0px 20px 20px 20px; color: #6b7280;")
        main_layout.addWidget(subtitle)

        # Tab Widget
        self.tabs = QTabWidget()
        self.tabs.setStyleSheet(
            """
            QTabWidget::pane { border: 1px solid #e5e7eb; }
            QTabBar::tab {
                background: #f3f4f6;
                border: 1px solid #e5e7eb;
                padding: 12px 24px;
                margin-right: 2px;
                color: #6b7280;
                font-weight: 600;
            }
            QTabBar::tab:selected {
                background: white;
                color: #2563eb;
                border-bottom: 3px solid #2563eb;
            }
            QTabBar::tab:hover:!selected {
                background: #f9fafb;
            }
            """
        )

        # Install Tab
        self._build_install_tab()

        # Installed Apps Tab
        self._build_installed_tab()

        main_layout.addWidget(self.tabs, 1)
        self.setCentralWidget(central)

    def _build_install_tab(self):
        """Build the app installation tab."""
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        # Description
        desc = QLabel("Scoop-Anwendungen suchen und installieren")
        desc.setStyleSheet("color: #6b7280; font-size: 12px;")
        layout.addWidget(desc)

        # Search controls
        search_layout = QHBoxLayout()
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("Scoop-Repository durchsuchen (z.B. brave, vscode)...")
        self.search_input.setMinimumHeight(40)
        self.search_input.returnPressed.connect(self._start_search)
        search_layout.addWidget(self.search_input)

        self.search_btn = QPushButton("🔍 Suchen")
        self.search_btn.setMinimumHeight(40)
        self.search_btn.setMaximumWidth(120)
        self.search_btn.clicked.connect(self._start_search)
        search_layout.addWidget(self.search_btn)

        layout.addLayout(search_layout)

        # Selection buttons
        selection_layout = QHBoxLayout()
        btn_select_all = QPushButton("☑ Alle auswählen")
        btn_select_all.setMinimumHeight(36)
        btn_select_all.clicked.connect(self._select_all)
        selection_layout.addWidget(btn_select_all)

        btn_clear = QPushButton("☐ Sichtbare Auswahl löschen")
        btn_clear.setMinimumHeight(36)
        btn_clear.clicked.connect(self._clear_selection)
        selection_layout.addWidget(btn_clear)

        btn_clear_all = QPushButton("🗑 ALLE Auswahlen löschen")
        btn_clear_all.setMinimumHeight(36)
        btn_clear_all.clicked.connect(self._clear_all_selection)
        selection_layout.addWidget(btn_clear_all)

        layout.addLayout(selection_layout)

        # Progress bar
        self.search_spinner = QProgressBar()
        self.search_spinner.setRange(0, 0)
        self.search_spinner.setFixedHeight(6)
        self.search_spinner.hide()
        layout.addWidget(self.search_spinner)

        # Results area
        self.results_group = QGroupBox("Suchergebnisse")
        self.results_group.setStyleSheet("QGroupBox { font-weight: 600; color: #1f2937; }")
        self.results_layout = QVBoxLayout(self.results_group)
        self.results_layout.setAlignment(Qt.AlignTop)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(self.results_group)
        layout.addWidget(scroll, 1)

        # Install progress
        self.install_spinner = QProgressBar()
        self.install_spinner.setRange(0, 0)
        self.install_spinner.setFixedHeight(6)
        self.install_spinner.hide()
        layout.addWidget(self.install_spinner)

        # Install button
        self.install_btn = QPushButton("⬇ Ausgewählte Apps installieren")
        self.install_btn.setMinimumHeight(44)
        self.install_btn.setStyleSheet("font-weight: 600; font-size: 13px;")
        self.install_btn.clicked.connect(self._start_install)
        layout.addWidget(self.install_btn)

        # Log
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setPlaceholderText("Status und Protokolle erscheinen hier...")
        self.log.setMaximumHeight(150)
        layout.addWidget(self.log)

        self.tabs.addTab(tab, "📦 Apps installieren")

    def _build_installed_tab(self):
        """Build the installed apps management tab."""
        tab = QWidget()
        layout = QVBoxLayout(tab)
        layout.setSpacing(15)
        layout.setContentsMargins(20, 20, 20, 20)

        # Description
        desc = QLabel("Installierte Scoop-Anwendungen anzeigen und verwalten")
        desc.setStyleSheet("color: #6b7280; font-size: 12px;")
        layout.addWidget(desc)

        # Refresh button
        refresh_layout = QHBoxLayout()
        self.refresh_btn = QPushButton("🔄 Liste aktualisieren")
        self.refresh_btn.setMinimumHeight(40)
        self.refresh_btn.setMinimumWidth(180)
        self.refresh_btn.clicked.connect(self._refresh_installed_list)
        refresh_layout.addWidget(self.refresh_btn)
        refresh_layout.addStretch()
        layout.addLayout(refresh_layout)

        # Progress bar
        self.refresh_spinner = QProgressBar()
        self.refresh_spinner.setRange(0, 0)
        self.refresh_spinner.setFixedHeight(6)
        self.refresh_spinner.hide()
        layout.addWidget(self.refresh_spinner)

        # Installed apps list
        self.installed_group = QGroupBox("Installierte Anwendungen")
        self.installed_group.setStyleSheet("QGroupBox { font-weight: 600; color: #1f2937; }")
        self.installed_layout = QVBoxLayout(self.installed_group)
        self.installed_layout.setAlignment(Qt.AlignTop)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(self.installed_group)
        layout.addWidget(scroll, 1)

        # Uninstall progress
        self.uninstall_spinner = QProgressBar()
        self.uninstall_spinner.setRange(0, 0)
        self.uninstall_spinner.setFixedHeight(6)
        self.uninstall_spinner.hide()
        layout.addWidget(self.uninstall_spinner)

        # Selection buttons for installed apps
        button_layout = QHBoxLayout()
        btn_select_all_inst = QPushButton("☑ Alle auswählen")
        btn_select_all_inst.setMinimumHeight(36)
        btn_select_all_inst.clicked.connect(self._select_all_installed)
        button_layout.addWidget(btn_select_all_inst)

        btn_clear_inst = QPushButton("☐ Auswahl löschen")
        btn_clear_inst.setMinimumHeight(36)
        btn_clear_inst.clicked.connect(self._clear_selection_installed)
        button_layout.addWidget(btn_clear_inst)

        layout.addLayout(button_layout)

        # Uninstall button
        self.uninstall_btn = QPushButton("🗑 Ausgewählte Apps deinstallieren")
        self.uninstall_btn.setMinimumHeight(44)
        self.uninstall_btn.setStyleSheet("font-weight: 600; font-size: 13px;")
        self.uninstall_btn.clicked.connect(self._start_uninstall)
        layout.addWidget(self.uninstall_btn)

        # Log
        self.log_uninstall = QPlainTextEdit()
        self.log_uninstall.setReadOnly(True)
        self.log_uninstall.setPlaceholderText("Status und Protokolle erscheinen hier...")
        self.log_uninstall.setMaximumHeight(150)
        layout.addWidget(self.log_uninstall)

        self.tabs.addTab(tab, "✅ Apps verwalten")

    def _apply_style(self):
        self.setStyleSheet(
            """
            QMainWindow { background: #ffffff; }
            
            QGroupBox {
                border: 1px solid #e5e7eb;
                border-radius: 12px;
                margin-top: 12px;
                padding: 15px;
                background: #fafbfc;
                font-weight: 600;
                color: #1f2937;
            }
            
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 10px;
                padding: 0px 3px 0px 3px;
            }
            
            QLabel { color: #1f2937; }
            
            QLineEdit {
                border: 1px solid #d0d7e2;
                border-radius: 8px;
                padding: 10px;
                background: #ffffff;
                color: #1f2937;
                selection-background-color: #2563eb;
            }
            
            QLineEdit:focus {
                border: 2px solid #2563eb;
            }
            
            QPlainTextEdit {
                border: 1px solid #d0d7e2;
                border-radius: 8px;
                padding: 10px;
                background: #ffffff;
                color: #1f2937;
            }
            
            QPushButton {
                background: #2563eb;
                color: white;
                border: none;
                border-radius: 8px;
                padding: 10px 16px;
                font-weight: 600;
                font-size: 13px;
            }
            
            QPushButton:hover:!disabled {
                background: #1d4ed8;
            }
            
            QPushButton:pressed:!disabled {
                background: #1e40af;
            }
            
            QPushButton:disabled {
                background: #d1d5db;
                color: #9ca3af;
            }
            
            QCheckBox {
                padding: 8px;
                color: #1f2937;
                font-size: 13px;
            }
            
            QCheckBox::indicator {
                width: 20px;
                height: 20px;
            }
            
            QCheckBox::indicator:unchecked {
                border: 2px solid #cbd5e1;
                border-radius: 4px;
                background: white;
            }
            
            QCheckBox::indicator:checked {
                border: 2px solid #2563eb;
                border-radius: 4px;
                background: #2563eb;
            }
            
            QScrollArea {
                border: none;
                background: transparent;
            }
            
            QScrollBar:vertical {
                background: #f3f4f6;
                width: 12px;
                border-radius: 6px;
            }
            
            QScrollBar::handle:vertical {
                background: #cbd5e1;
                border-radius: 6px;
                min-height: 20px;
            }
            
            QScrollBar::handle:vertical:hover {
                background: #9ca3af;
            }
            
            QProgressBar {
                border: none;
                background: #e5e7eb;
                border-radius: 4px;
                height: 6px;
            }
            
            QProgressBar::chunk {
                background-color: #2563eb;
                border-radius: 4px;
            }
            """
        )

    def _fade_in(self, widget, duration=250):
        # Keep for initial window only; do not apply to results list
        effect = widget.graphicsEffect()
        if not isinstance(effect, QGraphicsOpacityEffect):
            effect = QGraphicsOpacityEffect(widget)
            widget.setGraphicsEffect(effect)
        if self._fade_anim:
            self._fade_anim.stop()
            self._fade_anim.deleteLater()
        self._fade_anim = QPropertyAnimation(effect, b"opacity", self)
        self._fade_anim.setDuration(duration)
        self._fade_anim.setStartValue(effect.opacity())
        self._fade_anim.setEndValue(1.0)
        self._fade_anim.start()

    def _clear_results(self):
        for i in reversed(range(self.results_layout.count())):
            item = self.results_layout.takeAt(i)
            w = item.widget()
            if w:
                w.deleteLater()
        self._checkboxes.clear()

    def _clear_installed_results(self):
        for i in reversed(range(self.installed_layout.count())):
            item = self.installed_layout.takeAt(i)
            w = item.widget()
            if w:
                w.deleteLater()
        self._installed_checkboxes.clear()

    def _render_results(self, apps: list[str]):
        self._clear_results()
        for app in apps:
            cb = QCheckBox(app)
            cb.app_id = app  # type: ignore[attr-defined]
            # Check if this app was previously selected
            if app in self._selected_apps:
                cb.setChecked(True)
            # Track selection changes
            cb.stateChanged.connect(lambda checked, app_name=app: self._update_selection(app_name, checked))
            self.results_layout.addWidget(cb)
            self._checkboxes.append(cb)
        if not apps:
            self.results_layout.addWidget(QLabel("Keine Ergebnisse gefunden."))

    def _render_installed(self, apps: list[str]):
        self._clear_installed_results()
        if not apps:
            self.installed_layout.addWidget(QLabel("Keine Anwendungen installiert."))
            return
        for app in apps:
            cb = QCheckBox(app)
            cb.app_id = app  # type: ignore[attr-defined]
            self.installed_layout.addWidget(cb)
            self._installed_checkboxes.append(cb)

    def _start_search(self):
        self._trigger_search(explicit=True)

    def _update_selection(self, app_name: str, checked: int) -> None:
        """Track selected apps across searches."""
        if checked:
            self._selected_apps.add(app_name)
        else:
            self._selected_apps.discard(app_name)
    def _trigger_search(self, explicit=False):
        term = self.search_input.text()
        if not term or len(term.strip()) < 2:
            if explicit:
                QMessageBox.information(self, "Info", "Bitte geben Sie mindestens 2 Zeichen ein.")
            return
        
        # Notify user if this is a first-time search (not cached)
        if not installer.is_search_cached(term):
            QMessageBox.information(
                self,
                "Erstmalige Suche",
                f"Suche nach '{term}' zum ersten Mal.\n\n"
                "Dies kann einen Moment dauern, da Ergebnisse von Scoop abgerufen werden.\n"
                "Zukünftige Suchen nach diesem Begriff werden sofort sein (gecacht)."
            )
        
        self._log(f"Suche nach '{term}'...")
        self.search_btn.setEnabled(False)
        self.install_btn.setEnabled(False)
        self.search_spinner.show()
        self.worker_search = SearchThread(term)
        self.worker_search.progress.connect(self._log)
        self.worker_search.results.connect(self._on_search_results)
        self.worker_search.failed.connect(self._on_search_failed)
        self.worker_search.finished.connect(lambda: self.search_btn.setEnabled(True))
        self.worker_search.finished.connect(lambda: self.install_btn.setEnabled(True))
        self.worker_search.finished.connect(self.search_spinner.hide)
        self.worker_search.start()

    def _on_search_results(self, apps: list[str]):
        self._log(f"✓ {len(apps)} Anwendung(en) gefunden.")
        self._render_results(apps)

    def _on_search_failed(self, message: str):
        self._log(f"✗ Suche fehlgeschlagen: {message}")
        QMessageBox.critical(self, "Suche fehlgeschlagen", message)

    def _select_all(self):
        for cb in self._checkboxes:
            if cb.isVisible():
                cb.setChecked(True)

    def _clear_selection(self):
        # Only clear selections currently visible in the results list
        for cb in self._checkboxes:
            if cb.isChecked():
                self._selected_apps.discard(cb.app_id)  # type: ignore[attr-defined]
            cb.setChecked(False)

    def _clear_all_selection(self):
        # Confirm before clearing every tracked selection across all searches
        reply = QMessageBox.question(
            self,
            "Alle Auswahlen löschen",
            "Dadurch werden alle ausgewählten Apps über alle Suchen hinweg entfernt. Fortfahren?",
            QMessageBox.Yes | QMessageBox.No,
        )
        if reply != QMessageBox.Yes:
            return

        self._selected_apps.clear()
        for cb in self._checkboxes:
            cb.setChecked(False)

    def _select_all_installed(self):
        for cb in self._installed_checkboxes:
            if cb.isVisible():
                cb.setChecked(True)

    def _clear_selection_installed(self):
        for cb in self._installed_checkboxes:
            cb.setChecked(False)

    def _start_install(self):
        # Use the tracked selection across searches
        selected = sorted(self._selected_apps)
        if not selected:
            QMessageBox.information(self, "Info", "Bitte wählen Sie mindestens eine App zur Installation aus.")
            return

        # Skip apps that are already installed
        already = [app for app in selected if app.lower() in self._installed_apps]
        selected = [app for app in selected if app.lower() not in self._installed_apps]

        if already and not selected:
            QMessageBox.information(
                self,
                "Bereits installiert",
                "Alle ausgewählten Apps sind bereits installiert:\n\n" + ", ".join(already[:5]) + ("..." if len(already) > 5 else ""),
            )
            return
        if already:
            QMessageBox.information(
                self,
                "Installierte Apps überspringen",
                "Bereits installierte App(s) werden übersprungen:\n\n" + ", ".join(already[:5]) + ("..." if len(already) > 5 else ""),
            )
        reply = QMessageBox.question(
            self,
            "Installation bestätigen",
            f"{len(selected)} Anwendung(en) installieren?\n\n{', '.join(selected[:5])}{'...' if len(selected) > 5 else ''}",
            QMessageBox.Yes | QMessageBox.No,
        )
        if reply != QMessageBox.Yes:
            return
        self._log(f"Starte Installation von {len(selected)} App(s)...")
        self.install_btn.setEnabled(False)
        self.install_spinner.show()
        self.worker = InstallThread(selected)
        self.worker.progress.connect(self._log)
        self.worker.failed.connect(self._on_fail)
        self.worker.finished_ok.connect(self._on_success)
        self.worker.finished.connect(lambda: self.install_btn.setEnabled(True))
        self.worker.finished.connect(self.install_spinner.hide)
        self.worker.start()

    def _refresh_installed_list(self):
        self._log_uninstall("Aktualisiere installierte Anwendungen...")
        self.refresh_btn.setEnabled(False)
        self.uninstall_btn.setEnabled(False)
        self.refresh_spinner.show()
        self.worker_list = uninstaller.ListInstalledThread()
        self.worker_list.progress.connect(self._log_uninstall)
        self.worker_list.results.connect(self._on_installed_list_results)
        self.worker_list.failed.connect(self._on_installed_list_failed)
        self.worker_list.finished.connect(lambda: self.refresh_btn.setEnabled(True))
        self.worker_list.finished.connect(lambda: self.uninstall_btn.setEnabled(True))
        self.worker_list.finished.connect(self.refresh_spinner.hide)
        self.worker_list.start()

    def _on_installed_list_results(self, apps: list[str]):
        self._log_uninstall(f"✓ {len(apps)} installierte Anwendung(en) gefunden.")
        # Keep a lowercase set for quick membership checks during install
        self._installed_apps = {app.lower() for app in apps}
        self._render_installed(apps)

    def _on_installed_list_failed(self, message: str):
        self._log_uninstall(f"✗ Fehler beim Auflisten der Apps: {message}")
        QMessageBox.critical(self, "Fehler", message)

    def _start_uninstall(self):
        selected = [cb.app_id for cb in self._installed_checkboxes if cb.isChecked()]  # type: ignore[attr-defined]
        if not selected:
            QMessageBox.information(self, "Info", "Bitte wählen Sie mindestens eine App zur Deinstallation aus.")
            return
        reply = QMessageBox.question(
            self,
            "Deinstallation bestätigen",
            f"{len(selected)} Anwendung(en) deinstallieren?\n\n{', '.join(selected[:5])}{'...' if len(selected) > 5 else ''}",
            QMessageBox.Yes | QMessageBox.No,
        )
        if reply != QMessageBox.Yes:
            return
        self._log_uninstall(f"Starte Deinstallation von {len(selected)} App(s)...")
        self.uninstall_btn.setEnabled(False)
        self.uninstall_spinner.show()
        self.worker_uninstall = uninstaller.UninstallThread(selected)
        self.worker_uninstall.progress.connect(self._log_uninstall)
        self.worker_uninstall.failed.connect(self._on_uninstall_fail)
        self.worker_uninstall.finished_ok.connect(self._on_uninstall_success)
        self.worker_uninstall.finished.connect(lambda: self.uninstall_btn.setEnabled(True))
        self.worker_uninstall.finished.connect(self.uninstall_spinner.hide)
        self.worker_uninstall.start()

    def _log(self, message: str):
        self.log.appendPlainText(message)

    def _log_uninstall(self, message: str):
        self.log_uninstall.appendPlainText(message)

    def _on_success(self):
        self._log("✓ Installation erfolgreich abgeschlossen.")
        QMessageBox.information(self, "Erfolg", "Alle ausgewählten Apps wurden installiert.")

    def _on_fail(self, message: str):
        self._log(f"✗ Fehler: {message}")
        QMessageBox.critical(self, "Installation fehlgeschlagen", message)

    def _on_uninstall_success(self):
        self._log_uninstall("✓ Deinstallation erfolgreich abgeschlossen.")
        QMessageBox.information(self, "Erfolg", "Alle ausgewählten Apps wurden deinstalliert.")
        self._refresh_installed_list()

    def _on_uninstall_fail(self, message: str):
        self._log_uninstall(f"✗ Fehler: {message}")
        QMessageBox.critical(self, "Deinstallation fehlgeschlagen", message)


def launch_app(argv=None):
    app = QApplication(argv or [])
    win = MenuWindow()
    win.show()
    sys.exit(app.exec())
