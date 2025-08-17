import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_core/core.dart';

/// อ่านไลเซนส์ Syncfusion จาก --dart-define (ตั้งใน GitHub Secrets ชื่อ SYNCFUSION_LICENSE)
const _sfl = String.fromEnvironment('SYNCFUSION_LICENSE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ลงทะเบียนคีย์ Syncfusion ถ้ามี
  if (_sfl.isNotEmpty) {
    SyncfusionLicense.registerLicense(_sfl);
  }
  bool cloudReady = false;
  try {
    await Firebase.initializeApp();
    await FirebaseAuth.instance.signInAnonymously();
    cloudReady = true;
  } catch (_) {
    // ถ้าไม่มี google-services.json / ไม่ได้ตั้งค่า ก็ยังรันแบบ offline ได้
    cloudReady = false;
  }
  runApp(PDFProApp(cloudReady: cloudReady));
}

class PDFProApp extends StatelessWidget {
  final bool cloudReady;
  const PDFProApp({super.key, required this.cloudReady});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Reader Pro',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: HomePage(cloudReady: cloudReady),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  final bool cloudReady;
  const HomePage({super.key, required this.cloudReady});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _lastFileName;
  int? _lastPage;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastFileName = prefs.getString('last_file_name');
      _lastPage = prefs.getInt('last_page');
    });
  }

  Future<void> _openPicker() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final file = res.files.single;
    final data = file.bytes ?? await File(file.path!).readAsBytes();

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewerPage(
          fileName: file.name,
          pdfBytes: data,
          cloudReady: widget.cloudReady,
        ),
      ),
    ).then((_) => _loadLast());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF Reader Pro')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.cloudReady
                ? 'ซิงก์เปิดใช้งานแล้ว: last page / bookmarks / highlights จะบันทึกขึ้นคลาวด์'
                : 'โหมดออฟไลน์: ยังใช้งานอ่าน/จำหน้า/บุ๊คมาร์ก/โน้ตแบบโลคัลได้ (ยังไม่ซิงก์)'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openPicker,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('เปิดไฟล์ PDF'),
            ),
            const SizedBox(height: 24),
            if (_lastFileName != null && _lastPage != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(_lastFileName!),
                  subtitle: Text('ค้างที่หน้า $_lastPage'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ViewerPage extends StatefulWidget {
  final String fileName;
  final Uint8List pdfBytes;
  final bool cloudReady;
  const ViewerPage({
    super.key,
    required this.fileName,
    required this.pdfBytes,
    required this.cloudReady,
  });
  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfKey = GlobalKey();

  int _currentPage = 1;
  int _totalPages = 1;
  double _targetZoom = 1.0;
  Offset? _lastTapLocal;

  late final String _docId;

  @override
  void initState() {
    super.initState();
    _docId = _stableDocId(widget.pdfBytes, widget.fileName);
  }

  String _stableDocId(Uint8List bytes, String name) {
    final n = bytes.length;
    int h = 0;
    final len = bytes.length < 65536 ? bytes.length : 65536;
    for (int i = 0; i < len; i++) {
      h = (h * 131 + bytes[i]) & 0x7fffffff;
    }
    return 'v2::$h::$n::$name';
  }

  Future<void> _saveLocalSession(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_page', page);
    await prefs.setString('last_file_name', widget.fileName);
  }

  // ---------- Cloud helpers ----------
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('pdf_sessions');

  Future<void> _syncLastPage(int page) async {
    if (!widget.cloudReady) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await _col.doc('${uid}__$_docId').set({
        'uid': uid,
        'docId': _docId,
        'fileName': widget.fileName,
        'lastPage': page,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore in offline mode
    }
  }

  Future<void> _addBookmark() async {
    final page = _controller.pageNumber;
    final title = await _prompt(context, 'ชื่อบุ๊คมาร์ก', hint: 'เช่น บทที่ 2');
    if (title == null) return;

    if (widget.cloudReady) {
      try {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        await _col.doc('${uid}__$_docId').collection('bookmarks').add({
          'page': page,
          'title': title,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    } else {
      final prefs = await SharedPreferences.getInstance();
      final key = 'bm@$_docId';
      final list = List<String>.from(prefs.getStringList(key) ?? []);
      list.add('$page::$title');
      await prefs.setStringList(key, list);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('บันทึกบุ๊คมาร์กที่หน้า $page')));
    }
  }

  Future<void> _showBookmarks() async {
    if (!mounted) return;
    if (widget.cloudReady) {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _col
              .doc('${uid}__$_docId')
              .collection('bookmarks')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (c, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                  padding: EdgeInsets.all(20), child: Text('ยังไม่มีบุ๊คมาร์ก'));
            }
            return ListView(
              children: [
                for (final d in docs)
                  ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(d['title'] ?? 'bookmark'),
                    subtitle: Text('หน้า ${d['page']}'),
                    onTap: () {
                      Navigator.pop(context);
                      _controller.jumpToPage(d['page']);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => d.reference.delete(),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    } else {
      final prefs = await SharedPreferences.getInstance();
      final key = 'bm@$_docId';
      final list = List<String>.from(prefs.getStringList(key) ?? []);
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => list.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20), child: Text('ยังไม่มีบุ๊คมาร์ก'))
            : ListView(
                children: [
                  for (final s in list)
                    Builder(builder: (context) {
                      final parts = s.split('::');
                      final page = int.tryParse(parts.first) ?? 1;
                      final title = parts.skip(1).join('::');
                      return ListTile(
                        leading: const Icon(Icons.bookmark_border),
                        title: Text(title),
                        subtitle: Text('หน้า $page'),
                        onTap: () {
                          Navigator.pop(context);
                          _controller.jumpToPage(page);
                        },
                      );
                    })
                ],
              ),
      );
    }
  }

  // ---------- Notes / Highlights (บันทึกข้อความที่เลือก & หน้า) ----------
  Future<void> _saveHighlightOrNote({
    required String type, // 'highlight' | 'note'
    required String text,
    String? note,
  }) async {
    final page = _controller.pageNumber;
    if (widget.cloudReady) {
      try {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        await _col.doc('${uid}__$_docId').collection('marks').add({
          'type': type,
          'page': page,
          'text': text,
          'note': note,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    } else {
      final prefs = await SharedPreferences.getInstance();
      final key = 'marks@$_docId';
      final list = List<String>.from(prefs.getStringList(key) ?? []);
      // เก็บเป็นรูปแบบง่าย ๆ
      list.add('$type::$page::$text::${note ?? ''}');
      await prefs.setStringList(key, list);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(type == 'highlight'
              ? 'บันทึกไฮไลท์แล้ว (หน้า $page)'
              : 'บันทึกโน้ตแล้ว (หน้า $page)')));
    }
  }

  Future<void> _showMarksList() async {
    if (widget.cloudReady) {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _col
              .doc('${uid}__$_docId')
              .collection('marks')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (c, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                  padding: EdgeInsets.all(20), child: Text('ยังไม่มีไฮไลท์/โน้ต'));
            }
            return ListView(
              children: [
                for (final d in docs)
                  ListTile(
                    leading: Icon(d['type'] == 'note'
                        ? Icons.sticky_note_2_outlined
                        : Icons.highlight),
                    title: Text(d['type'] == 'note'
                        ? (d['note'] ?? '(ไม่มีข้อความ)')
                        : (d['text'] ?? '(ไม่มีข้อความ)')),
                    subtitle: Text('หน้า ${d['page']}'),
                    onTap: () {
                      Navigator.pop(context);
                      _controller.jumpToPage(d['page']);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => d.reference.delete(),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    } else {
      final prefs = await SharedPreferences.getInstance();
      final key = 'marks@$_docId';
      final list = List<String>.from(prefs.getStringList(key) ?? []);
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => list.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20), child: Text('ยังไม่มีไฮไลท์/โน้ต'))
            : ListView(
                children: [
                  for (final s in list)
                    Builder(builder: (context) {
                      final parts = s.split('::');
                      final type = parts[0];
                      final page = int.tryParse(parts[1]) ?? 1;
                      final text = parts[2];
                      final note = parts.length > 3 ? parts[3] : '';
                      return ListTile(
                        leading: Icon(type == 'note'
                            ? Icons.sticky_note_2_outlined
                            : Icons.highlight),
                        title: Text(type == 'note' ? note : text),
                        subtitle: Text('หน้า $page'),
                        onTap: () {
                          Navigator.pop(context);
                          _controller.jumpToPage(page);
                        },
                      );
                    })
                ],
              ),
      );
    }
  }

  // ---------- Zoom to finger (double-tap) ----------
  void _handleDoubleTapDown(TapDownDetails d) {
    _lastTapLocal = d.localPosition;
  }

  void _handleDoubleTap() {
    _targetZoom = (_controller.zoomLevel < 2.0) ? 2.5 : 1.0;
    _controller.zoomLevel = _targetZoom;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.fileName} — $_currentPage/$_totalPages'),
        actions: [
          IconButton(
            tooltip: 'บุ๊คมาร์ก',
            onPressed: _addBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          IconButton(
            tooltip: 'รายการบุ๊คมาร์ก',
            onPressed: _showBookmarks,
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            tooltip: 'ไฮไลท์/โน้ตทั้งหมด',
            onPressed: _showMarksList,
            icon: const Icon(Icons.note_alt_outlined),
          ),
        ],
      ),
      body: GestureDetector(
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,
        child: SfPdfViewer.memory(
          widget.pdfBytes,
          key: _pdfKey,
          controller: _controller,
          maxZoomLevel: 5,
          canShowScrollHead: true,
          canShowPaginationDialog: true,
          onDocumentLoaded: (details) async {
            _totalPages = details.document.pagesCount;
            final prefs = await SharedPreferences.getInstance();
            final page = prefs.getInt('last_page') ?? 1;
            _controller.jumpToPage(page);
            setState(() {});
          },
          onPageChanged: (d) async {
            _currentPage = d.newPageNumber;
            await _saveLocalSession(_currentPage);
            await _syncLastPage(_currentPage);
            setState(() {});
          },
          onTextSelectionChanged: (details) async {
            final sel = details.selectedText;
            if (sel == null || sel.isEmpty) return;
            // แสดงกล่องเลือกว่าจะทำเป็นไฮไลท์ หรือจดโน้ต
            final action = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (_) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('เลือกที่ต้องการทำกับข้อความที่เลือก:', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      ListTile(
                        leading: const Icon(Icons.highlight),
                        title: const Text('บันทึกเป็นไฮไลท์'),
                        onTap: () => Navigator.pop(context, 'highlight'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.sticky_note_2_outlined),
                        title: const Text('จดโน้ตแนบข้อความนี้'),
                        onTap: () => Navigator.pop(context, 'note'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
            if (!mounted || action == null) return;

            if (action == 'highlight') {
              await _saveHighlightOrNote(type: 'highlight', text: sel);
            } else if (action == 'note') {
              final note = await _prompt(context, 'จดโน้ต', hint: 'พิมพ์โน้ตที่นี่');
              if (note != null) {
                await _saveHighlightOrNote(type: 'note', text: sel, note: note);
              }
            }
            _pdfKey.currentState?.clearSelection();
          },
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'prev',
            onPressed: () => _controller.previousPage(
                duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
            child: const Icon(Icons.chevron_left),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'next',
            onPressed: () => _controller.nextPage(
                duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
            child: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, {String? hint}) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctrl, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()), child: const Text('ตกลง')),
      ],
    ),
  );
}
