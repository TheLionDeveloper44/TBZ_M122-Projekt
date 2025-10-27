from PySide6.QtWidgets import QApplication, QWidget, QLabel, QPushButton, QVBoxLayout, QLineEdit
import sys

class SimpleWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("My Simple PySide6 GUI")
        self.setGeometry(100, 100, 300, 200)

        # Widgets
        self.label = QLabel("Enter your name below:")
        self.text_input = QLineEdit()
        self.button = QPushButton("Say Hello")
        self.output_label = QLabel("")

        # Button action
        self.button.clicked.connect(self.say_hello)

        # Layout
        layout = QVBoxLayout()
        layout.addWidget(self.label)
        layout.addWidget(self.text_input)
        layout.addWidget(self.button)
        layout.addWidget(self.output_label)
        self.setLayout(layout)

    def say_hello(self):
        name = self.text_input.text().strip()
        if name:
            self.output_label.setText(f"Hello, {name}!")
        else:
            self.output_label.setText("Please enter your name!")

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = SimpleWindow()
    window.show()
    sys.exit(app.exec())
