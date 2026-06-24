/*
  Copyright (c) 2014 Paul Stoffregen <paul@pjrc.com>

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

// adapted from https://community.oracle.com/thread/1479784

package processing.app;

import javax.swing.JTextArea;
import javax.swing.event.DocumentEvent;
import javax.swing.event.DocumentListener;
import javax.swing.text.BadLocationException;

public class TextAreaFIFO extends JTextArea implements DocumentListener {
  private final int maxChars;
  private final int trimTarget;

  public TextAreaFIFO(int max) {
    maxChars = max;
    trimTarget = max * 6 / 10;
    getDocument().addDocumentListener(this);
  }

  @Override
  public void append(String str) {
    appendWithTrim(str);
  }

  public void appendWithTrim(String str) {
    if (str == null || str.isEmpty()) {
      return;
    }
    makeRoom(str.length());
    super.append(str);
  }

  public void appendWithoutTrim(String str) {
    if (str == null || str.isEmpty()) {
      return;
    }
    int len = getDocument().getLength();
    if (len >= maxChars) {
      return;
    }
    int free = maxChars - len;
    if (str.length() > free) {
      str = str.substring(0, free);
    }
    super.append(str);
  }

  private void makeRoom(int incomingLen) {
    int len = getDocument().getLength();
    int afterAppend = len + incomingLen;
    if (afterAppend <= trimTarget) {
      return;
    }
    int targetLen = Math.max(0, trimTarget - incomingLen);
    if (len > targetLen) {
      removeFromStart(len - targetLen);
    }
  }

  private void removeFromStart(int count) {
    if (count <= 0) {
      return;
    }
    try {
      getDocument().remove(0, count);
    } catch (BadLocationException ignored) {
    }
  }

  public void trimDocument() {
    int len = getDocument().getLength();
    if (len > trimTarget) {
      removeFromStart(len - trimTarget);
    }
  }

  @Override
  public void insertUpdate(DocumentEvent e) {
    int len = getDocument().getLength();
    if (len > maxChars) {
      removeFromStart(len - trimTarget);
    }
  }

  @Override
  public void removeUpdate(DocumentEvent e) {
  }

  @Override
  public void changedUpdate(DocumentEvent e) {
  }
}
