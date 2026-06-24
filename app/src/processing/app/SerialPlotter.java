/* -*- mode: java; c-basic-offset: 2; indent-tabs-mode: nil -*- */

/*
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software Foundation,
  Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

package processing.app;

import cc.arduino.packages.BoardPort;
import processing.app.helpers.CircularBuffer;
import processing.app.helpers.Ticks;
import processing.app.legacy.PApplet;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.util.ArrayList;
import javax.swing.*;
import javax.swing.border.EmptyBorder;
import javax.swing.text.DefaultEditorKit;
import java.awt.*;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;
import java.awt.geom.AffineTransform;
import java.awt.geom.Rectangle2D;

import static processing.app.I18n.tr;

public class SerialPlotter extends AbstractMonitor {

  private static final int MESSAGE_BUFFER_MAX = 65536;

  private final StringBuffer messageBuffer = new StringBuffer();
  protected JComboBox<String> serialRates;
  protected Serial serial;
  private int serialRate, xCount;

  protected JLabel noLineEndingAlert;
  protected JTextField textField;
  protected JButton sendButton;
  protected JComboBox<String> lineEndings;

  private ArrayList<Graph> graphs = new ArrayList<>();
  private final static int BUFFER_CAPACITY = 500;

  private final boolean teensyPipe;
  private String teensyName;
  private String openPort;
  private Process program;
  private InputPlotterPipeListener listener;
  private ErrorPlotterPipeListener errors;
  private Thread shutdownHook;

  private static class Graph {
    public CircularBuffer buffer;
    private Color color;
    public String label;

    public Graph(int id) {
      buffer = new CircularBuffer(BUFFER_CAPACITY);
      color = Theme.getColorCycleColor("plotting.graphcolor", id);
    }

    public void paint(Graphics2D g, float xstep, double minY,
                      double maxY, double rangeY, double height) {
      g.setColor(color);
      g.setStroke(new BasicStroke(1.0f));

      for (int i = 0; i < buffer.size() - 1; ++i) {
        g.drawLine(
          (int) (i * xstep), (int) transformY(buffer.get(i), minY, rangeY, height),
          (int) ((i + 1) * xstep), (int) transformY(buffer.get(i + 1), minY, rangeY, height)
        );
      }
    }

    private float transformY(double rawY, double minY, double rangeY, double height) {
      return (float) (5 + (height - 10) * (1.0 - (rawY - minY) / rangeY));
    }
  }

  private class GraphPanel extends JPanel {
    private double minY, maxY, rangeY;
    private Rectangle bounds;
    private int xOffset, xPadding;
    private final Font font;
    private final Color bgColor, gridColor, boundsColor;

    public GraphPanel() {
      font = Theme.getFont("console.font");
      bgColor = Theme.getColor("plotting.bgcolor");
      gridColor = Theme.getColor("plotting.gridcolor");
      boundsColor = Theme.getColor("plotting.boundscolor");
      xOffset = 20;
      xPadding = 20;
    }

    private Ticks computeBounds() {
      minY = Double.POSITIVE_INFINITY;
      maxY = Double.NEGATIVE_INFINITY;
      for (Graph g : graphs) {
        if (!g.buffer.isEmpty()) {
          minY = Math.min(g.buffer.min(), minY);
          maxY = Math.max(g.buffer.max(), maxY);
        }
      }

      if (minY == Double.POSITIVE_INFINITY || maxY == Double.NEGATIVE_INFINITY) {
        minY = 0;
        maxY = 10;
      }

      final double MIN_DELTA = 10.0;
      if (maxY - minY < MIN_DELTA) {
        double mid = (maxY + minY) / 2;
        maxY = mid + MIN_DELTA / 2;
        minY = mid - MIN_DELTA / 2;
      }

      Ticks ticks = new Ticks(minY, maxY, 5);
      if (ticks.getTickCount() == 0) {
        minY = 0;
        maxY = 10;
        rangeY = 10;
        return new Ticks(minY, maxY, 5);
      }
      minY = Math.min(minY, ticks.getTick(0));
      maxY = Math.max(maxY, ticks.getTick(ticks.getTickCount() - 1));
      rangeY = maxY - minY;
      minY -= 0.05 * rangeY;
      maxY += 0.05 * rangeY;
      rangeY = maxY - minY;
      return ticks;
    }

    @Override
    public void paintComponent(Graphics g1) {
      Graphics2D g = (Graphics2D) g1;
      g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
      g.setFont(font);
      super.paintComponent(g);

      bounds = g.getClipBounds();
      setBackground(bgColor);
      if (graphs.isEmpty()) {
        return;
      }

      Ticks ticks = computeBounds();
      int tickCount = ticks.getTickCount();
      if (tickCount == 0) {
        return;
      }

      g.setStroke(new BasicStroke(1.0f));
      FontMetrics fm = g.getFontMetrics();
      for (int i = 0; i < tickCount; ++i) {
        double tick = ticks.getTick(i);
        Rectangle2D fRect = fm.getStringBounds(String.valueOf(tick), g);
        xOffset = Math.max(xOffset, (int) fRect.getWidth() + 15);

        g.setColor(boundsColor);
        g.drawLine(xOffset - 5, (int) transformY(tick), xOffset + 2, (int) transformY(tick));
        g.drawString(String.valueOf(tick), xOffset - (int) fRect.getWidth() - 10, transformY(tick) - (float) fRect.getHeight() * 0.5f + fm.getAscent());
        g.setColor(gridColor);
        g.drawLine(xOffset + 3, (int) transformY(tick), bounds.width - xPadding, (int) transformY(tick));
      }

      int cnt = xCount - BUFFER_CAPACITY;
      if (xCount < BUFFER_CAPACITY) cnt = 0;

      double zeroTick = ticks.getTick(0);
      double lastTick = ticks.getTick(tickCount - 1);
      double xTickRange = BUFFER_CAPACITY / (double) tickCount;

      for (int i = 0; i < tickCount + 1; i++) {
        String s;
        int xValue;
        int sWidth;
        Rectangle2D fBounds;
        if (i == 0) {
          s = String.valueOf(cnt);
          fBounds = fm.getStringBounds(s, g);
          sWidth = (int) fBounds.getWidth() / 2;
          xValue = xOffset;
        } else {
          s = String.valueOf((int) (xTickRange * i) + cnt);
          fBounds = fm.getStringBounds(s, g);
          sWidth = (int) fBounds.getWidth() / 2;
          xValue = (int) ((bounds.width - xOffset - xPadding) * ((xTickRange * i) / BUFFER_CAPACITY) + xOffset);
        }
        g.setColor(boundsColor);
        g.drawString(s, xValue - sWidth, (int) bounds.y + (int) transformY(zeroTick) + 15);
        g.drawLine(xValue, (int) transformY(zeroTick) - 2, xValue, bounds.y + (int) transformY(zeroTick) + 5);
        g.setColor(gridColor);
        g.drawLine(xValue, (int) transformY(zeroTick) - 3, xValue, bounds.y + (int) transformY(lastTick));
      }
      g.setColor(boundsColor);
      g.drawLine(bounds.x + xOffset, (int) transformY(lastTick) - 5, bounds.x + xOffset, bounds.y + (int) transformY(zeroTick) + 5);
      g.drawLine(xOffset, (int) transformY(zeroTick), bounds.width - xPadding, (int) transformY(zeroTick));

      g.setTransform(AffineTransform.getTranslateInstance(xOffset, 0));
      float xstep = (float) (bounds.width - xOffset - xPadding) / (float) BUFFER_CAPACITY;

      int legendXOffset = 0;
      for (int i = 0; i < graphs.size(); ++i) {
        graphs.get(i).paint(g, xstep, minY, maxY, rangeY, bounds.height);
        if (graphs.size() > 1) {
          g.fillRect(10 + legendXOffset, 10, 10, 10);
          legendXOffset += 13;
          g.setColor(boundsColor);
          String s = graphs.get(i).label;
          if (s != null && s.length() > 0) {
            Rectangle2D fBounds = fm.getStringBounds(s, g);
            int sWidth = (int) fBounds.getWidth();
            g.drawString(s, 10 + legendXOffset, 10 + (int) fBounds.getHeight() / 2);
            legendXOffset += sWidth + 3;
          }
        }
      }
    }

    private float transformY(double rawY) {
      return (float) (5 + (bounds.height - 10) * (1.0 - (rawY - minY) / rangeY));
    }

    @Override
    public Dimension getMinimumSize() {
      return new Dimension(200, 100);
    }

    @Override
    public Dimension getPreferredSize() {
      return new Dimension(500, 250);
    }
  }

  public SerialPlotter(BoardPort port) {
    super(port);

    teensyPipe = isTeensyPort(port);
    if (teensyPipe) {
      teensyName = parseTeensyName(port);
      serialRates.setVisible(false);
      disconnect();
      return;
    }

    serialRate = PreferencesData.getInteger("serial.debug_rate");
    serialRates.setSelectedItem(serialRate + " " + tr("baud"));
    onSerialRateChange(event -> {
      String wholeString = (String) serialRates.getSelectedItem();
      String rateString = wholeString.substring(0, wholeString.indexOf(' '));
      serialRate = Integer.parseInt(rateString);
      PreferencesData.set("serial.debug_rate", rateString);
      if (serial != null) {
        try {
          close();
          Thread.sleep(100);
          open();
        } catch (Exception e) {
          // ignore
        }
      }
    });
  }

  private static boolean isTeensyPort(BoardPort port) {
    String protocol = port.getProtocol();
    return (protocol != null && protocol.equalsIgnoreCase("Teensy"))
        || port.getAddress().startsWith("usb:");
  }

  private static String parseTeensyName(BoardPort port) {
    String[] pieces = port.getLabel().trim().split("[\\(\\)]");
    if (pieces.length > 2 && pieces[1].startsWith("Teensy")) {
      return pieces[1];
    }
    return "Teensy";
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

  protected void onCreateWindow(Container mainPane) {
    mainPane.setLayout(new BorderLayout());

    GraphPanel graphPanel = new GraphPanel();
    mainPane.add(graphPanel, BorderLayout.CENTER);

    JPanel pane = new JPanel();
    pane.setLayout(new BoxLayout(pane, BoxLayout.X_AXIS));
    pane.setBorder(new EmptyBorder(4, 4, 4, 4));

    serialRates = new JComboBox<>();
    for (String serialRateString : serialRateStrings) {
      serialRates.addItem(serialRateString + " " + tr("baud"));
    }
    serialRates.setMaximumSize(serialRates.getMinimumSize());

    pane.add(Box.createHorizontalGlue());
    pane.add(Box.createRigidArea(new Dimension(8, 0)));
    pane.add(serialRates);
    mainPane.add(pane, BorderLayout.SOUTH);

    textField = new JTextField(40);
    addWindowFocusListener(new WindowAdapter() {
      @Override
      public void windowGainedFocus(WindowEvent e) {
        textField.requestFocusInWindow();
      }
    });

    JPopupMenu menu = new JPopupMenu();
    Action cut = new DefaultEditorKit.CutAction();
    cut.putValue(Action.NAME, tr("Cut"));
    menu.add(cut);
    Action copy = new DefaultEditorKit.CopyAction();
    copy.putValue(Action.NAME, tr("Copy"));
    menu.add(copy);
    Action paste = new DefaultEditorKit.PasteAction();
    paste.putValue(Action.NAME, tr("Paste"));
    menu.add(paste);
    textField.setComponentPopupMenu(menu);

    sendButton = new JButton(tr("Send"));

    JPanel lowerPane = new JPanel();
    lowerPane.setLayout(new BoxLayout(lowerPane, BoxLayout.X_AXIS));
    lowerPane.setBorder(new EmptyBorder(4, 4, 4, 4));

    noLineEndingAlert = new JLabel(I18n.format(tr("You've pressed {0} but nothing was sent. Should you select a line ending?"), tr("Send")));
    noLineEndingAlert.setToolTipText(noLineEndingAlert.getText());
    noLineEndingAlert.setForeground(pane.getBackground());
    Dimension minimumSize = new Dimension(noLineEndingAlert.getMinimumSize());
    minimumSize.setSize(minimumSize.getWidth() / 3, minimumSize.getHeight());
    noLineEndingAlert.setMinimumSize(minimumSize);

    lineEndings = new JComboBox<>(new String[]{
      tr("No line ending"), tr("Newline"), tr("Carriage return"), tr("Both NL & CR")
    });
    lineEndings.addActionListener((ActionEvent event) -> {
      PreferencesData.setInteger("serial.line_ending", lineEndings.getSelectedIndex());
      noLineEndingAlert.setForeground(pane.getBackground());
    });
    lineEndings.setMaximumSize(lineEndings.getMinimumSize());

    lowerPane.add(textField);
    lowerPane.add(Box.createRigidArea(new Dimension(4, 0)));
    lowerPane.add(sendButton);

    pane.add(lowerPane);
    pane.add(noLineEndingAlert);
    pane.add(Box.createRigidArea(new Dimension(8, 0)));
    pane.add(lineEndings);

    applyPreferences();

    onSendCommand((ActionEvent event) -> {
      send(textField.getText());
      textField.setText("");
    });
  }

  private void send(String string) {
    String s = string;
    switch (lineEndings.getSelectedIndex()) {
      case 1: s += "\n"; break;
      case 2: s += "\r"; break;
      case 3: s += "\r\n"; break;
      default: break;
    }
    if ("".equals(s) && lineEndings.getSelectedIndex() == 0
        && !PreferencesData.has("runtime.line.ending.alert.notified")) {
      noLineEndingAlert.setForeground(Color.RED);
      PreferencesData.set("runtime.line.ending.alert.notified", "true");
    }

    if (teensyPipe) {
      if (program == null) {
        return;
      }
      OutputStream out = program.getOutputStream();
      if (out != null) {
        try {
          out.write(s.getBytes());
          out.flush();
        } catch (Exception ignored) {
        }
      }
      return;
    }

    if (serial != null) {
      serial.write(s);
    }
  }

  public void onSendCommand(ActionListener listener) {
    textField.addActionListener(listener);
    sendButton.addActionListener(listener);
  }

  public void applyPreferences() {
    if (PreferencesData.get("serial.line_ending") != null) {
      lineEndings.setSelectedIndex(PreferencesData.getInteger("serial.line_ending"));
    }
  }

  protected void onEnableWindow(boolean enable) {
    textField.setEnabled(enable);
    sendButton.setEnabled(enable);
  }

  private void onSerialRateChange(ActionListener listener) {
    serialRates.addActionListener(listener);
  }

  public void message(final String s) {
    if (s == null || s.isEmpty()) {
      return;
    }
    messageBuffer.append(s);
    if (messageBuffer.length() > MESSAGE_BUFFER_MAX) {
      messageBuffer.delete(0, messageBuffer.length() - MESSAGE_BUFFER_MAX / 2);
    }

    boolean updated = false;
    while (true) {
      int linebreak = messageBuffer.indexOf("\n");
      if (linebreak == -1) {
        break;
      }
      xCount++;
      String line = messageBuffer.substring(0, linebreak);
      messageBuffer.delete(0, linebreak + 1);

      line = line.trim();
      if (line.length() == 0) {
        continue;
      }
      String[] parts = line.split("[, \t]+");
      if (parts.length == 0) {
        continue;
      }

      int validParts = 0;
      int validLabels = 0;
      for (int i = 0; i < parts.length; ++i) {
        Double value = null;
        String label = null;

        if (parts[i].contains(":")) {
          String[] subString = parts[i].split("[:]+");
          if (subString.length > 0) {
            int labelLength = Math.min(subString[0].length(), 32);
            label = subString[0].substring(0, labelLength);
          } else {
            label = "";
          }
          parts[i] = subString.length > 1 ? subString[1] : "";
        }

        try {
          value = Double.valueOf(parts[i]);
        } catch (NumberFormatException e) {
          // ignored
        }
        if (label == null && value == null) {
          label = parts[i];
        }

        if (value != null) {
          if (validParts >= graphs.size()) {
            graphs.add(new Graph(validParts));
          }
          graphs.get(validParts).buffer.add(value);
          validParts++;
          updated = true;
        }
        if (label != null) {
          if (validLabels >= graphs.size()) {
            graphs.add(new Graph(validLabels));
          }
          graphs.get(validLabels).label = label;
          validLabels++;
        }
        if (validParts > validLabels) validLabels = validParts;
        else if (validLabels > validParts) validParts = validLabels;
      }
    }

    if (updated) {
      repaint();
    }
  }

  public void open() throws Exception {
    super.open();
    if (teensyPipe) {
      openTeensyPipe();
      return;
    }
    openSerialPort();
  }

  private void openTeensyPipe() throws Exception {
    String port = getBoardPort().getAddress();
    if (openPort != null && port.equals(openPort) && program != null
        && listener != null && listener.isAlive()
        && errors != null && errors.isAlive()) {
      return;
    }
    if (program != null || listener != null || errors != null) {
      closeTeensyPipe(false);
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
    listener = new InputPlotterPipeListener(program.getInputStream(), this);
    listener.start();
    errors = new ErrorPlotterPipeListener(program.getErrorStream(), this);
    errors.start();

    if (shutdownHook != null) {
      try {
        Runtime.getRuntime().removeShutdownHook(shutdownHook);
      } catch (Exception ignored) {
      }
    }
    shutdownHook = new Thread(this::destroyTeensyPipeProcess);
    Runtime.getRuntime().addShutdownHook(shutdownHook);
  }

  private void openSerialPort() throws Exception {
    if (serial != null) {
      return;
    }

    int attempt = 1;
    while (true) {
      try {
        serial = new Serial(getBoardPort().getAddress(), serialRate) {
          @Override
          protected void message(char buff[], int n) {
            addToUpdateBuffer(buff, n);
          }
        };
        break;
      } catch (SerialException e) {
        if (++attempt > 20) {
          throw e;
        }
      }
      Thread.sleep(100);
    }
  }

  public void close() throws Exception {
    if (teensyPipe) {
      closeTeensyPipe(true);
      return;
    }
    if (serial != null) {
      super.close();
      int[] location = getPlacement();
      String locationStr = PApplet.join(PApplet.str(location), ",");
      PreferencesData.set("last.serial.location", locationStr);
      serial.dispose();
      serial = null;
    }
  }

  private void closeTeensyPipe(boolean saveLocation) throws Exception {
    destroyTeensyPipeProcess();
    if (shutdownHook != null) {
      try {
        Runtime.getRuntime().removeShutdownHook(shutdownHook);
      } catch (Exception ignored) {
      }
      shutdownHook = null;
    }
    openPort = null;
    setTitle("[offline] (" + teensyName + ")");
    if (saveLocation) {
      int[] location = getPlacement();
      String locationStr = PApplet.join(PApplet.str(location), ",");
      PreferencesData.set("last.serial.location", locationStr);
    }
    super.close();
  }

  private void destroyTeensyPipeProcess() {
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
  }

  void opened(String device, String usbType) {
    SwingUtilities.invokeLater(() -> {
      setTitle(device + " (" + teensyName + ") " + usbType);
      graphs.clear();
      xCount = 0;
      messageBuffer.setLength(0);
      enableWindow(true);
      repaint();
    });
  }

  void disconnect() {
    setTitle("[offline] (" + teensyName + ")");
    messageBuffer.setLength(0);
    enableWindow(false);
  }

  private static class InputPlotterPipeListener extends Thread {
    private final InputStream input;
    private final SerialPlotter output;

    InputPlotterPipeListener(InputStream input, SerialPlotter output) {
      this.input = input;
      this.output = output;
      setName("SerialPlotter input");
    }

    @Override
    public void run() {
      byte[] buffer = new byte[65536];
      try {
        while (output.program != null && !Thread.interrupted()) {
          int count = input.read(buffer);
          if (count <= 0) {
            break;
          }
          String text = new String(buffer, 0, count);
          char[] chars = text.toCharArray();
          output.addToUpdateBuffer(chars, chars.length);
        }
      } catch (Exception ignored) {
      }
    }
  }

  private static class ErrorPlotterPipeListener extends Thread {
    private final InputStream input;
    private final SerialPlotter output;

    ErrorPlotterPipeListener(InputStream input, SerialPlotter output) {
      this.input = input;
      this.output = output;
      setName("SerialPlotter errors");
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
            SwingUtilities.invokeLater(output::disconnect);
          } else {
            System.err.println(line);
          }
        }
      } catch (Exception ignored) {
      }
    }
  }
}
