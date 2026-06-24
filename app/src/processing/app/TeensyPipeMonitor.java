/*
  Teensy serial monitor — talks to teensy_serialmon over stdin/stdout.
  Adapted from Teensyduino (Paul Stoffregen), simplified for this build.
*/

package processing.app;

import cc.arduino.packages.BoardPort;

import java.awt.Color;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.BufferedReader;
import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import javax.swing.SwingUtilities;

public class TeensyPipeMonitor extends AbstractTextMonitor {

  private String teensyName;
  private String openPort;
  private Process program;
  private InputPipeListener listener;
  private ErrorPipeListener errors;

  public TeensyPipeMonitor(BoardPort port) {
    super(port);
    String[] pieces = port.getLabel().trim().split("[\\(\\)]");
    if (pieces.length > 2 && pieces[1].startsWith("Teensy")) {
      teensyName = pieces[1];
    } else {
      teensyName = "Teensy";
    }
    serialRates.setVisible(false);
    addTimeStampBox.setVisible(false);
    if (serialRates.getParent() != null) {
      serialRates.getParent().remove(serialRates);
    }
    disconnect();
    revalidate();

    onClearCommand((ActionEvent e) -> clear());

    onSendCommand((ActionEvent e) -> {
      String s = textField.getText();
      switch (lineEndings.getSelectedIndex()) {
        case 1: s += "\n"; break;
        case 2: s += "\r"; break;
        case 3: s += "\r\n"; break;
        default: break;
      }
      if (program != null) {
        OutputStream out = program.getOutputStream();
        if (out != null) {
          try {
            out.write(s.getBytes());
            out.flush();
          } catch (Exception ignored) {
          }
        }
      }
      textField.setText("");
    });
  }

  private static File teensySerialmonBinary() {
    File hardware = BaseNoGui.getHardwareFolder();
    File[] candidates = {
      new File(hardware, "teensy/tools/teensy_serialmon"),
      new File(hardware, "tools/teensy_serialmon"),
    };
    for (File candidate : candidates) {
      if (candidate.canExecute()) {
        return candidate;
      }
    }
    return candidates[0];
  }

  private void clear() {
    textArea.select(0, 0);
    textArea.setCaretPosition(0);
    textArea.setText("");
  }

  @Override
  public void open() throws Exception {
    String port = getBoardPort().getAddress();
    if (openPort != null && port.equals(openPort) && program != null
        && listener != null && listener.isAlive()
        && errors != null && errors.isAlive()) {
      return;
    }
    if (program != null || listener != null || errors != null) {
      close();
    }

    File command = teensySerialmonBinary();
    if (!command.canExecute()) {
      throw new Exception("teensy_serialmon not found: " + command.getAbsolutePath());
    }

    program = Runtime.getRuntime().exec(new String[] {
      command.getAbsolutePath(),
      port,
    });

    openPort = port;
    clear();
    listener = new InputPipeListener(program.getInputStream(), this);
    listener.start();
    errors = new ErrorPipeListener(program.getErrorStream(), this);
    errors.start();
    super.open();
  }

  @Override
  public void close() throws Exception {
    if (program != null) {
      program.destroy();
      program = null;
    }
    if (listener != null) {
      if (listener.isAlive()) {
        listener.interrupt();
      }
      listener = null;
    }
    if (errors != null) {
      if (errors.isAlive()) {
        errors.interrupt();
      }
      errors = null;
    }
    openPort = null;
    setTitle("[offline] (" + teensyName + ")");
    super.close();
  }

  void opened(String device, String usbType) {
    clear();
    setTitle(device + " (" + teensyName + ") " + usbType);
    enableWindow(true);
  }

  void disconnect() {
    setTitle("[offline] (" + teensyName + ")");
    enableWindow(false);
  }

  @Override
  protected void onEnableWindow(boolean enable) {
    textArea.setEnabled(true);
    if (enable) {
      textArea.setForeground(Color.BLACK);
      textArea.setBackground(Color.WHITE);
    } else {
      textArea.setForeground(new Color(64, 64, 64));
      textArea.setBackground(new Color(238, 238, 238));
    }
    textArea.invalidate();
    clearButton.setEnabled(enable);
    scrollPane.setEnabled(enable);
    textField.setEnabled(enable);
    sendButton.setEnabled(enable);
    autoscrollBox.setEnabled(enable);
    addTimeStampBox.setEnabled(enable);
    lineEndings.setEnabled(enable);
    serialRates.setEnabled(enable);
  }

  private static class InputPipeListener extends Thread {
    private final InputStream input;
    private final TeensyPipeMonitor output;

    InputPipeListener(InputStream input, TeensyPipeMonitor output) {
      this.input = input;
      this.output = output;
      setName("TeensyPipeMonitor input");
    }

    @Override
    public void run() {
      try (InputStreamReader reader = new InputStreamReader(input)) {
        char[] buffer = new char[4096];
        while (output.program != null && !Thread.interrupted()) {
          if (!reader.ready()) {
            Thread.sleep(1);
            continue;
          }
          int count = reader.read(buffer);
          if (count <= 0) {
            break;
          }
          output.addToUpdateBuffer(buffer, count);
          SwingUtilities.invokeLater(() -> output.actionPerformed(null));
          if (output.autoscrollBox.isSelected()) {
            output.textArea.setCaretPosition(output.textArea.getDocument().getLength());
          }
        }
      } catch (Exception ignored) {
      } finally {
        try {
          output.close();
        } catch (Exception e) {
          output.disconnect();
        }
      }
    }
  }

  private static class ErrorPipeListener extends Thread {
    private final InputStream input;
    private final TeensyPipeMonitor output;

    ErrorPipeListener(InputStream input, TeensyPipeMonitor output) {
      this.input = input;
      this.output = output;
      setName("TeensyPipeMonitor errors");
    }

    @Override
    public void run() {
      try (BufferedReader in = new BufferedReader(new InputStreamReader(input))) {
        while (output.program != null) {
          String line = in.readLine();
          if (line == null) {
            break;
          }
          if (line.startsWith("Opened ")) {
            String[] parts = line.trim().split(" ", 3);
            if (parts.length == 3) {
              output.opened(parts[1], parts[2]);
            }
          } else if (line.startsWith("Disconnect ")) {
            output.disconnect();
          } else {
            System.err.println(line);
          }
        }
      } catch (Exception ignored) {
      }
    }
  }
}
