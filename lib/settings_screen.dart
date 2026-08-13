// settings_screen.dart
//
// Settings page for Clean Spirit AI.
// Shows downloaded models with download / delete actions,
// plus general app settings (incognito default, theme, etc.)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_loader.dart';

// ---------------------------------------------------------------------------
// Prefs keys (shared with chat_screen if needed)
// ---------------------------------------------------------------------------

const String kPrefDefaultIncognito = 'default_incognito';
const String kPrefFontSize         = 'font_size';          // 'small'|'medium'|'large'
const String kPrefSendOnEnter      = 'send_on_enter';

// ---------------------------------------------------------------------------
// SettingsScreen
// ---------------------------------------------------------------------------

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Model state
  bool _gemmaDownloaded   = false;
  bool _gemmaE4bDownloaded = false;
  bool _qwenDownloaded    = false;
  bool _gemmaDownloading  = false;
  bool _gemmaE4bDownloading = false;
  bool _qwenDownloading   = false;
  double _gemmaProgress   = 0;
  double _gemmaE4bProgress = 0;
  double _qwenProgress    = 0;
  bool _gemmaDeleting     = false;
  bool _gemmaE4bDeleting  = false;
  bool _qwenDeleting      = false;

  // General prefs
  bool   _defaultIncognito = false;
  bool   _sendOnEnter      = true;
  String _fontSize         = 'medium';

  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadPrefs();
  }

  Future<void> _refresh() async {
    final g = await ModelLoader.isGemmaDownloaded();
    final g4b = await ModelLoader.isGemmaE4bDownloaded();
    final q = await ModelLoader.isQwen4bDownloaded();
    if (mounted) {
      setState(() {
        _gemmaDownloaded = g;
        _gemmaE4bDownloaded = g4b;
        _qwenDownloaded = q;
      });
    }
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _defaultIncognito = p.getBool(kPrefDefaultIncognito) ?? false;
        _sendOnEnter      = p.getBool(kPrefSendOnEnter)      ?? true;
        _fontSize         = p.getString(kPrefFontSize)        ?? 'medium';
        _prefsLoaded      = true;
      });
    }
  }

  Future<void> _setPref(String key, dynamic value) async {
    final p = await SharedPreferences.getInstance();
    if (value is bool)   await p.setBool(key, value);
    if (value is String) await p.setString(key, value);
  }

  // ---- model helpers -------------------------------------------------------

  Future<int?> _fileSize(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/models/$fileName');
    if (await f.exists()) return await f.length();
    return null;
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _downloadModel(ModelVariant variant) async {
    setState(() {
      if (variant == ModelVariant.gemma) {
        _gemmaDownloading = true;
        _gemmaProgress = 0;
      } else if (variant == ModelVariant.gemmaE4b) {
        _gemmaE4bDownloading = true;
        _gemmaE4bProgress = 0;
      } else {
        _qwenDownloading = true;
        _qwenProgress = 0;
      }
    });
    try {
      await ModelLoader.downloadModel(
        variant: variant,
        onProgress: (p) {
          if (mounted) setState(() {
            if (variant == ModelVariant.gemma) {
              _gemmaProgress = p;
            } else if (variant == ModelVariant.gemmaE4b) {
              _gemmaE4bProgress = p;
            } else {
              _qwenProgress = p;
            }
          });
        },
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed - $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() {
        if (variant == ModelVariant.gemma) {
          _gemmaDownloading = false;
        } else if (variant == ModelVariant.gemmaE4b) {
          _gemmaE4bDownloading = false;
        } else {
          _qwenDownloading = false;
        }
      });
    }
  }

  Future<void> _deleteModel(ModelVariant variant) async {
    final name = switch (variant) {
      ModelVariant.gemma => 'Gemma 4 E2B',
      ModelVariant.gemmaE4b => 'Gemma 4 E4B',
      ModelVariant.qwen4b => 'Qwen3 4B',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text('This will remove $name from your device. You can re-download it later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      if (variant == ModelVariant.gemma) {
        _gemmaDeleting = true;
      } else if (variant == ModelVariant.gemmaE4b) {
        _gemmaE4bDeleting = true;
      } else {
        _qwenDeleting = true;
      }
    });
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = switch (variant) {
        ModelVariant.gemma => kGemmaFileName,
        ModelVariant.gemmaE4b => kGemmaE4bFileName,
        ModelVariant.qwen4b => kQwen4bFileName,
      };
      final f = File('${dir.path}/models/$fileName');
      if (await f.exists()) await f.delete();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed - $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() {
        if (variant == ModelVariant.gemma) {
          _gemmaDeleting = false;
        } else if (variant == ModelVariant.gemmaE4b) {
          _gemmaE4bDeleting = false;
        } else {
          _qwenDeleting = false;
        }
      });
    }
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final surface = theme.colorScheme.surfaceContainerHighest;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [

          // ---- Models section ----------------------------------------------
          _SectionHeader(label: 'Models', accent: accent),

          _ModelCard(
            title: 'Gemma 4 E2B',
            subtitle: 'GPU - vision-capable - fast',
            sizeLabel: kGemmaSizeLabel,
            icon: Icons.memory_rounded,
            accent: accent,
            surface: surface,
            theme: theme,
            downloaded: _gemmaDownloaded,
            downloading: _gemmaDownloading,
            progress: _gemmaProgress,
            deleting: _gemmaDeleting,
            fileSizeFuture: _fileSize(kGemmaFileName),
            fmtBytes: _fmtBytes,
            onDownload: () => _downloadModel(ModelVariant.gemma),
            onDelete:   () => _deleteModel(ModelVariant.gemma),
            onCancel:   () async {
              await ModelLoader.cancelDownload();
              setState(() { _gemmaDownloading = false; _gemmaProgress = 0; });
            },
          ),

          const SizedBox(height: 10),

          _ModelCard(
            title: 'Gemma 4 E4B',
            subtitle: 'GPU - higher quality - needs ~5 GB RAM',
            sizeLabel: kGemmaE4bSizeLabel,
            icon: Icons.auto_awesome_rounded,
            accent: accent,
            surface: surface,
            theme: theme,
            downloaded: _gemmaE4bDownloaded,
            downloading: _gemmaE4bDownloading,
            progress: _gemmaE4bProgress,
            deleting: _gemmaE4bDeleting,
            fileSizeFuture: _fileSize(kGemmaE4bFileName),
            fmtBytes: _fmtBytes,
            onDownload: () => _downloadModel(ModelVariant.gemmaE4b),
            onDelete:   () => _deleteModel(ModelVariant.gemmaE4b),
            onCancel:   () async {
              await ModelLoader.cancelDownload();
              setState(() {
                _gemmaE4bDownloading = false;
                _gemmaE4bProgress = 0;
              });
            },
          ),

          const SizedBox(height: 10),

          _ModelCard(
            title: 'Qwen3 4B',
            subtitle: 'CPU - thorough reasoning',
            sizeLabel: kQwen4bSizeLabel,
            icon: Icons.psychology_rounded,
            accent: accent,
            surface: surface,
            theme: theme,
            downloaded: _qwenDownloaded,
            downloading: _qwenDownloading,
            progress: _qwenProgress,
            deleting: _qwenDeleting,
            fileSizeFuture: _fileSize(kQwen4bFileName),
            fmtBytes: _fmtBytes,
            onDownload: () => _downloadModel(ModelVariant.qwen4b),
            onDelete:   () => _deleteModel(ModelVariant.qwen4b),
            onCancel:   () async {
              await ModelLoader.cancelDownload();
              setState(() { _qwenDownloading = false; _qwenProgress = 0; });
            },
          ),

          const SizedBox(height: 24),

          // ---- Chat behaviour section -------------------------------------
          _SectionHeader(label: 'Chat behaviour', accent: accent),

          if (_prefsLoaded) ...[
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: Icon(Icons.dark_mode_outlined, color: accent),
              title: const Text('Start in incognito mode',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: const Text('New conversations will not be saved by default'),
              value: _defaultIncognito,
              activeColor: accent,
              onChanged: (v) {
                setState(() => _defaultIncognito = v);
                _setPref(kPrefDefaultIncognito, v);
              },
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: Icon(Icons.keyboard_return_rounded, color: accent),
              title: const Text('Send on Enter',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: const Text('Press Enter to send - Shift+Enter for a new line'),
              value: _sendOnEnter,
              activeColor: accent,
              onChanged: (v) {
                setState(() => _sendOnEnter = v);
                _setPref(kPrefSendOnEnter, v);
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(Icons.format_size_rounded, color: accent),
              title: const Text('Response font size',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(_fontSize[0].toUpperCase() + _fontSize.substring(1)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final picked = await showDialog<String>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Font size'),
                    children: ['small', 'medium', 'large'].map((s) => RadioListTile<String>(
                      title: Text(s[0].toUpperCase() + s.substring(1)),
                      value: s,
                      groupValue: _fontSize,
                      activeColor: accent,
                      onChanged: (v) => Navigator.pop(ctx, v),
                    )).toList(),
                  ),
                );
                if (picked != null && mounted) {
                  setState(() => _fontSize = picked);
                  _setPref(kPrefFontSize, picked);
                }
              },
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),

          const SizedBox(height: 24),

          // ---- Storage section --------------------------------------------
          _SectionHeader(label: 'Storage', accent: accent),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.folder_outlined, color: accent),
            title: const Text('Model storage',
                style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Models stored in app-private documents folder'),
            trailing: const Icon(Icons.info_outline_rounded, size: 18),
          ),

          const SizedBox(height: 24),

          // ---- About section ----------------------------------------------
          _SectionHeader(label: 'About', accent: accent),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.info_outline_rounded, color: accent),
            title: const Text('Clean Spirit AI',
                style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('Version 0.2.0 - fully offline, no data leaves your device'),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.lock_outline_rounded, color: accent),
            title: const Text('Privacy',
                style: TextStyle(fontWeight: FontWeight.w500)),
            subtitle: const Text('No internet required after model download - no telemetry, no accounts'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color accent;
  const _SectionHeader({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: accent,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Model card widget
// ---------------------------------------------------------------------------

class _ModelCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String sizeLabel;
  final IconData icon;
  final Color accent;
  final Color surface;
  final ThemeData theme;
  final bool downloaded;
  final bool downloading;
  final double progress;
  final bool deleting;
  final Future<int?> fileSizeFuture;
  final String Function(int) fmtBytes;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _ModelCard({
    required this.title,
    required this.subtitle,
    required this.sizeLabel,
    required this.icon,
    required this.accent,
    required this.surface,
    required this.theme,
    required this.downloaded,
    required this.downloading,
    required this.progress,
    required this.deleting,
    required this.fileSizeFuture,
    required this.fmtBytes,
    required this.onDownload,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: downloaded
                ? accent.withValues(alpha: 0.35)
                : theme.colorScheme.outline.withValues(alpha: 0.15),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                // Status badge
                if (downloaded && !deleting)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 13, color: Colors.green.shade400),
                        const SizedBox(width: 4),
                        Text('Downloaded',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade400)),
                      ],
                    ),
                  )
                else if (!downloaded && !downloading && !deleting)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Not downloaded',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45))),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Size info row
            FutureBuilder<int?>(
              future: fileSizeFuture,
              builder: (ctx, snap) {
                final onDisk = snap.data;
                return Row(
                  children: [
                    Icon(Icons.storage_rounded,
                        size: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                    const SizedBox(width: 4),
                    Text(
                      onDisk != null
                          ? '${fmtBytes(onDisk)} on device'
                          : '$sizeLabel to download',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                );
              },
            ),

            // Download progress bar
            if (downloading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                  color: accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(progress * 100).toStringAsFixed(0)}% downloaded',
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ],

            const SizedBox(height: 14),

            // Action buttons
            Row(
              children: [
                if (!downloaded && !downloading)
                  FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Download'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (downloading)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (downloaded && !deleting) ...[
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 16, color: Colors.redAccent),
                    label: const Text('Delete',
                        style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                if (deleting) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  const Text('Deleting...', style: TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
