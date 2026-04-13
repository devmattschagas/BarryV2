import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.initialProfile});

  final UserProfile initialProfile;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final TextEditingController _nameController;
  String _avatarPath = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialProfile.name);
    _avatarPath = widget.initialProfile.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final result = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (result == null) return;
    setState(() => _avatarPath = result.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050C16),
      appBar: AppBar(backgroundColor: const Color(0xFF050C16), title: const Text('Conta do usuário')),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF071426), Color(0xFF050C16)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x7700E5FF)),
                color: const Color(0xFF0B1828),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Perfil local', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Center(
                    child: InkWell(
                      onTap: _pickAvatar,
                      borderRadius: BorderRadius.circular(64),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x7700E5FF)),
                          boxShadow: const [BoxShadow(color: Color(0x3300E5FF), blurRadius: 10)],
                        ),
                        child: CircleAvatar(
                          radius: 52,
                          backgroundImage: _avatarPath.isEmpty ? null : FileImage(File(_avatarPath)),
                          child: _avatarPath.isEmpty ? const Icon(Icons.person, size: 42) : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(child: Text('Toque para alterar foto')),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      labelText: 'Nome de usuário',
                      filled: true,
                      fillColor: const Color(0x22121824),
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(
                          UserProfile(
                            name: _nameController.text.trim().isEmpty ? 'Operador' : _nameController.text.trim(),
                            avatarPath: _avatarPath,
                          ),
                        );
                      },
                      child: const Text('Salvar perfil'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
