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
      appBar: AppBar(title: const Text('Conta do usuário')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            InkWell(
              onTap: _pickAvatar,
              borderRadius: BorderRadius.circular(60),
              child: CircleAvatar(
                radius: 48,
                backgroundImage: _avatarPath.isEmpty ? null : FileImage(File(_avatarPath)),
                child: _avatarPath.isEmpty ? const Icon(Icons.person, size: 42) : null,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Toque para alterar foto'),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Nome de usuário',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop(
                  UserProfile(
                    name: _nameController.text.trim().isEmpty ? 'Operador' : _nameController.text.trim(),
                    avatarPath: _avatarPath,
                  ),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Salvar perfil'),
            ),
          ],
        ),
      ),
    );
  }
}
