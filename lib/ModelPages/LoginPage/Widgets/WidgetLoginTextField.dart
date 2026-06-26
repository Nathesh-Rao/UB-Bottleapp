import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ubbottleapp/Constants/MyColors.dart';

import 'WidgetRotatingSuffixField.dart';

class WidgetLoginTextField extends StatefulWidget {
  const WidgetLoginTextField({
    super.key,
    required this.label,
    this.controller,
    this.errorText = '',
    this.hintText,
    this.suffixIcon,
    this.prefixIcon,
    this.obscureText = false,
    this.isLoading = false,
    this.readOnly = false,
    this.style2 = false,
    this.focusNode,
    this.onTap,
  });

  final String label;
  final TextEditingController? controller;
  final Widget? suffixIcon;
  final String? errorText;
  final bool obscureText;
  final bool isLoading;
  final bool readOnly;
  final String? hintText;
  final FocusNode? focusNode;
  final void Function()? onTap;
  final bool style2;

  final Widget? prefixIcon;
  @override
  State<WidgetLoginTextField> createState() => _WidgetLoginTextFieldState();
}

class _WidgetLoginTextFieldState extends State<WidgetLoginTextField> {
  late bool _isObscured;

  @override
  void initState() {
    super.initState();
    _isObscured = widget.obscureText;
  }

  void _toggleObscure() {
    setState(() {
      _isObscured = !_isObscured;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isPasswordField = widget.obscureText;
    return Padding(
      padding: const EdgeInsets.only(left: 25, right: 25, top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.style2
              ? SizedBox.shrink()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: !widget.errorText!.isEmpty
                            ? Theme.of(context).colorScheme.error
                            : Colors.black,
                      ),
                    ),
                    SizedBox(height: 10),
                  ],
                ),
          SizedBox(
            height: 55,
            child: Stack(
              children: [
                TextFormField(
                  cursorColor: MyColors.blue1,
                  focusNode: widget.focusNode,
                  controller: widget.controller,
                  readOnly:
                      !widget.isLoading ? widget.readOnly : widget.isLoading,
                  obscureText: _isObscured,
                  //widget.obscureText,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: MyColors.AXMDark,
                  ),
                  onTap: widget.onTap,

                  decoration: InputDecoration(
                    filled: widget.style2 ? true : null,
                    fillColor: widget.style2 ? Colors.white12 : null,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xff4B59D9).withValues(alpha: 0.5),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    //
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xff4B59D9).withValues(alpha: 0.5),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),

                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Color(0xff4B59D9).withValues(alpha: 0.7),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: widget.prefixIcon,
                    prefixIconColor: Color(0xff4B59D9),
                    // prefixIconColor: MyColors.AXMDark,
                    suffixIcon: Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: widget.isLoading
                          ? const WidgetRotatingSuffixField()
                          : isPasswordField
                              ? IconButton(
                                  onPressed: _toggleObscure,
                                  icon: Icon(
                                    _isObscured
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.grey,
                                  ),
                                )
                              : widget.suffixIcon ??
                                  Icon(
                                    Icons.circle,
                                    color: Colors.transparent,
                                  ),
                    ),
                    //
                    errorText:
                        widget.errorText!.isEmpty ? null : widget.errorText,
                    hintText: widget.hintText,
                    hintStyle: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.grey.shade400,
                    ),

                    //
                  ),
                ),
                //Positioned(right: 20, top: 0, bottom: 0, child: widget.isLoading ? WidgetRotatingSuffixField() : widget.suffixIcon ?? SizedBox.shrink())
                /* Positioned(
                  right: 20,
                  top: 0,
                  bottom: 0,
                  child: widget.isLoading
                      ? const WidgetRotatingSuffixField()
                      : isPasswordField
                          ? Center(
                              child: IconButton(
                                onPressed: _toggleObscure,
                                icon: Icon(
                                  _isObscured ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : widget.suffixIcon ?? const SizedBox.shrink(),
                ),*/
              ],
            ),
          ),
        ],
      ),
    );
  }
}
