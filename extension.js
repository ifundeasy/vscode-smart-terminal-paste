// Smart Terminal Paste
//
// Runs on the UI side (extensionKind "ui"), so it reads the clipboard of the machine
// the VS Code window is on, also in Remote-SSH / container windows.
//
//   clipboard has text   -> normal terminal paste (bracketed paste, same as Ctrl+Shift+V)
//   clipboard has no text -> send a literal Ctrl+V (0x16) to the terminal, so a program
//                            that binds Ctrl+V to image paste (e.g. Claude Code) handles it
const vscode = require('vscode');

const COMMAND = 'smartTerminalPaste.paste';

async function paste() {
  const text = await vscode.env.clipboard.readText();
  if (text && text.length > 0) {
    await vscode.commands.executeCommand('workbench.action.terminal.paste');
  } else {
    await vscode.commands.executeCommand('workbench.action.terminal.sendSequence', { text: '\u0016' });
  }
}

// A keybinding only reaches an extension command while the terminal has focus if that
// command is listed in terminal.integrated.commandsToSkipShell; otherwise the terminal
// consumes the key. Add it to the user settings once, unless the user opted out.
async function ensureSkipShell() {
  if (!vscode.workspace.getConfiguration('smartTerminalPaste').get('autoConfigure', true)) {
    return;
  }
  const terminal = vscode.workspace.getConfiguration('terminal.integrated');
  const current = terminal.inspect('commandsToSkipShell')?.globalValue ?? [];
  if (current.includes(COMMAND)) {
    return;
  }
  await terminal.update('commandsToSkipShell', [...current, COMMAND], vscode.ConfigurationTarget.Global);
}

exports.activate = (context) => {
  context.subscriptions.push(vscode.commands.registerCommand(COMMAND, paste));
  ensureSkipShell().catch((err) => {
    console.error('smart-terminal-paste: could not update terminal.integrated.commandsToSkipShell', err);
  });
};

exports.deactivate = () => {};
