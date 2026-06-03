import ast;
import interner;
import io;
import symbol;
import sys;
import token;

// Tree pretty-printer for the AST. Output is one line per node:
//   <indent>Kind <scalar-fields>
// Children print on subsequent lines at indent+1. The function is total over
// AstKind — unknown values produce "<unknown kind N>", a soft failure that
// makes a missing arm visible in tests rather than silently dropping the node.

export fn void print(ast::AstNode* n, interner::Interner* it, i32 indent, io::OutBuf* out) {
    write_indent(out, indent);
    if(!n) {
        io::outbuf_write(out, "<null>\n");
        return;
    }
    switch(n.h.kind) {
    case ast::AstKind::INVALID: { io::outbuf_write(out, "Invalid\n"); }
    case ast::AstKind::ERROR:   { io::outbuf_write(out, "Error\n"); }

    // declarations ///////////////////////////////////////////////////////////
    case ast::AstKind::ImportDecl: {
        ast::ImportNode* d = (ast::ImportNode*)n;
        io::outbuf_write(out, "Import ");
        write_sym(out, d.module_name, it);
        if(d.is_reexport) { io::outbuf_write(out, " reexport"); }
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::VarDecl: {
        ast::VarDeclNode* d = (ast::VarDeclNode*)n;
        io::outbuf_write(out, "VarDecl ");
        write_sym(out, d.name, it);
        if(d.is_const) { io::outbuf_write(out, " const"); }
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_labeled_child(out, indent + 1, "type", d.type_expr, it);
        write_labeled_child(out, indent + 1, "init", d.init, it);
    }
    case ast::AstKind::FnDecl: {
        ast::FnDeclNode* d = (ast::FnDeclNode*)n;
        io::outbuf_write(out, "FnDecl ");
        write_sym(out, d.name, it);
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_labeled_child(out, indent + 1, "return", d.return_type, it);
        write_params(out, indent + 1, d.params, it);
        write_labeled_child(out, indent + 1, "body", d.body, it);
    }
    case ast::AstKind::StructDecl: {
        ast::StructDeclNode* d = (ast::StructDeclNode*)n;
        io::outbuf_write(out, "StructDecl ");
        write_sym(out, d.name, it);
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_fields(out, indent + 1, d.fields, it);
    }
    case ast::AstKind::UnionDecl: {
        ast::UnionDeclNode* d = (ast::UnionDeclNode*)n;
        io::outbuf_write(out, "UnionDecl ");
        write_sym(out, d.name, it);
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_fields(out, indent + 1, d.fields, it);
    }
    case ast::AstKind::EnumDecl: {
        ast::EnumDeclNode* d = (ast::EnumDeclNode*)n;
        io::outbuf_write(out, "EnumDecl ");
        write_sym(out, d.name, it);
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_labeled_child(out, indent + 1, "base", d.base_type, it);
        write_enum_members(out, indent + 1, d.members, it);
    }
    case ast::AstKind::AliasDecl: {
        ast::AliasDeclNode* d = (ast::AliasDeclNode*)n;
        io::outbuf_write(out, "AliasDecl ");
        write_sym(out, d.name, it);
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_labeled_child(out, indent + 1, "target", d.target, it);
    }
    case ast::AstKind::ExternBlock: {
        ast::ExternBlockNode* d = (ast::ExternBlockNode*)n;
        io::outbuf_write(out, "ExternBlock ");
        if(d.lib_name) { write_sym(out, d.lib_name, it); }
        else           { io::outbuf_write(out, "c"); }
        io::outbuf_write_byte(out, '\n');
        write_children(out, indent + 1, d.items, it);
    }
    case ast::AstKind::ExternFnDecl: {
        ast::ExternFnDeclNode* d = (ast::ExternFnDeclNode*)n;
        io::outbuf_write(out, "ExternFnDecl ");
        write_sym(out, d.name, it);
        if(d.is_variadic) { io::outbuf_write(out, " variadic"); }
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_labeled_child(out, indent + 1, "return", d.return_type, it);
        write_params(out, indent + 1, d.params, it);
    }
    case ast::AstKind::ExternStructDecl: {
        ast::ExternStructDeclNode* d = (ast::ExternStructDeclNode*)n;
        io::outbuf_write(out, "ExternStructDecl ");
        write_sym(out, d.name, it);
        if(d.is_opaque)   { io::outbuf_write(out, " opaque"); }
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_fields(out, indent + 1, d.fields, it);
    }
    case ast::AstKind::ExternUnionDecl: {
        ast::ExternUnionDeclNode* d = (ast::ExternUnionDeclNode*)n;
        io::outbuf_write(out, "ExternUnionDecl ");
        write_sym(out, d.name, it);
        if(d.is_opaque)   { io::outbuf_write(out, " opaque"); }
        if(d.is_exported) { io::outbuf_write(out, " exported"); }
        io::outbuf_write_byte(out, '\n');
        write_fields(out, indent + 1, d.fields, it);
    }

    // statements /////////////////////////////////////////////////////////////
    case ast::AstKind::BlockStmt: {
        ast::BlockNode* s = (ast::BlockNode*)n;
        io::outbuf_write(out, "Block\n");
        write_children(out, indent + 1, s.stmts, it);
    }
    case ast::AstKind::IfStmt: {
        ast::IfNode* s = (ast::IfNode*)n;
        io::outbuf_write(out, "If\n");
        write_labeled_child(out, indent + 1, "cond", s.cond, it);
        write_labeled_child(out, indent + 1, "then", s.then_block, it);
        if(s.else_block) {
            write_labeled_child(out, indent + 1, "else", s.else_block, it);
        }
    }
    case ast::AstKind::WhileStmt: {
        ast::WhileNode* s = (ast::WhileNode*)n;
        io::outbuf_write(out, "While\n");
        write_labeled_child(out, indent + 1, "cond", s.cond, it);
        write_labeled_child(out, indent + 1, "body", s.body, it);
    }
    case ast::AstKind::ForStmt: {
        ast::ForNode* s = (ast::ForNode*)n;
        io::outbuf_write(out, "For\n");
        write_labeled_child(out, indent + 1, "init", s.init, it);
        write_labeled_child(out, indent + 1, "cond", s.cond, it);
        write_labeled_child(out, indent + 1, "post", s.post, it);
        write_labeled_child(out, indent + 1, "body", s.body, it);
    }
    case ast::AstKind::SwitchStmt: {
        ast::SwitchNode* s = (ast::SwitchNode*)n;
        io::outbuf_write(out, "Switch\n");
        write_labeled_child(out, indent + 1, "discriminant", s.discriminant, it);
        write_switch_arms(out, indent + 1, s.arms, it);
        if(s.else_block) {
            write_labeled_child(out, indent + 1, "else", s.else_block, it);
        }
    }
    case ast::AstKind::ReturnStmt: {
        ast::ReturnNode* s = (ast::ReturnNode*)n;
        io::outbuf_write(out, "Return\n");
        if(s.expr) { print(s.expr, it, indent + 1, out); }
    }
    case ast::AstKind::BreakStmt:    { io::outbuf_write(out, "Break\n"); }
    case ast::AstKind::ContinueStmt: { io::outbuf_write(out, "Continue\n"); }
    case ast::AstKind::DeferStmt: {
        ast::DeferNode* s = (ast::DeferNode*)n;
        io::outbuf_write(out, "Defer\n");
        print(s.body, it, indent + 1, out);
    }
    case ast::AstKind::AssignmentStmt: {
        ast::AssignmentNode* s = (ast::AssignmentNode*)n;
        io::outbuf_write(out, "Assign ");
        io::outbuf_write(out, token::kind_name(s.op));
        io::outbuf_write_byte(out, '\n');
        print(s.lhs, it, indent + 1, out);
        print(s.rhs, it, indent + 1, out);
    }
    case ast::AstKind::ExprStmt: {
        ast::ExprStmtNode* s = (ast::ExprStmtNode*)n;
        io::outbuf_write(out, "ExprStmt\n");
        print(s.expr, it, indent + 1, out);
    }
    case ast::AstKind::ComprunStmt: {
        ast::CompRunNode* s = (ast::CompRunNode*)n;
        io::outbuf_write(out, "Comprun\n");
        print(s.body, it, indent + 1, out);
    }
    case ast::AstKind::CompinsertStmt: {
        ast::CompInsertNode* s = (ast::CompInsertNode*)n;
        io::outbuf_write(out, "Compinsert\n");
        print(s.source_expr, it, indent + 1, out);
    }
    case ast::AstKind::CompspliceStmt: {
        ast::CompSpliceNode* s = (ast::CompSpliceNode*)n;
        io::outbuf_write(out, "Compsplice\n");
        print(s.code_expr, it, indent + 1, out);
    }
    case ast::AstKind::ComperrorStmt: {
        ast::CompErrorNode* s = (ast::CompErrorNode*)n;
        io::outbuf_write(out, "Comperror\n");
        print(s.msg_expr, it, indent + 1, out);
    }
    case ast::AstKind::CompwarningStmt: {
        ast::CompWarningNode* s = (ast::CompWarningNode*)n;
        io::outbuf_write(out, "Compwarning\n");
        print(s.msg_expr, it, indent + 1, out);
    }

    // expressions ////////////////////////////////////////////////////////////
    case ast::AstKind::IntLit: {
        ast::IntLitNode* e = (ast::IntLitNode*)n;
        io::outbuf_write(out, "IntLit ");
        io::outbuf_write_u64(out, e.value);
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::FloatLit: {
        ast::FloatLitNode* e = (ast::FloatLitNode*)n;
        io::outbuf_write(out, "FloatLit ");
        write_f64(out, e.value);
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::BoolLit: {
        ast::BoolLitNode* e = (ast::BoolLitNode*)n;
        if(e.value) { io::outbuf_write(out, "BoolLit true\n"); }
        else        { io::outbuf_write(out, "BoolLit false\n"); }
    }
    case ast::AstKind::CharLit: {
        ast::CharLitNode* e = (ast::CharLitNode*)n;
        io::outbuf_write(out, "CharLit ");
        io::outbuf_write_u64(out, (u64)e.value);
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::StringLit: {
        ast::StringLitNode* e = (ast::StringLitNode*)n;
        io::outbuf_write(out, "StringLit off=");
        io::outbuf_write_u64(out, (u64)e.pool_off);
        io::outbuf_write(out, " len=");
        io::outbuf_write_u64(out, (u64)e.pool_len);
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::NullLit:      { io::outbuf_write(out, "NullLit\n"); }
    case ast::AstKind::UndefinedLit: { io::outbuf_write(out, "UndefinedLit\n"); }
    case ast::AstKind::Ident: {
        ast::IdentNode* e = (ast::IdentNode*)n;
        io::outbuf_write(out, "Ident ");
        write_sym(out, e.name, it);
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::NamespaceAccess: {
        ast::NamespaceAccessNode* e = (ast::NamespaceAccessNode*)n;
        io::outbuf_write(out, "NamespaceAccess ");
        write_ns_chain(out, (ast::AstNode*)e, it);
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::MemberAccess: {
        ast::MemberAccessNode* e = (ast::MemberAccessNode*)n;
        io::outbuf_write(out, "MemberAccess .");
        write_sym(out, e.field, it);
        io::outbuf_write_byte(out, '\n');
        print(e.base, it, indent + 1, out);
    }
    case ast::AstKind::ArrayIndex: {
        ast::ArrayIndexNode* e = (ast::ArrayIndexNode*)n;
        io::outbuf_write(out, "ArrayIndex\n");
        write_labeled_child(out, indent + 1, "base", e.base, it);
        write_labeled_child(out, indent + 1, "index", e.index, it);
    }
    case ast::AstKind::SliceRange: {
        ast::SliceRangeNode* e = (ast::SliceRangeNode*)n;
        io::outbuf_write(out, "SliceRange\n");
        write_labeled_child(out, indent + 1, "base", e.base, it);
        write_labeled_child(out, indent + 1, "lo", e.lo, it);
        write_labeled_child(out, indent + 1, "hi", e.hi, it);
    }
    case ast::AstKind::Call: {
        ast::CallNode* e = (ast::CallNode*)n;
        io::outbuf_write(out, "Call\n");
        write_labeled_child(out, indent + 1, "callee", e.callee, it);
        write_indent(out, indent + 1);
        io::outbuf_write(out, "args\n");
        write_children(out, indent + 2, e.args, it);
    }
    case ast::AstKind::Cast: {
        ast::CastNode* e = (ast::CastNode*)n;
        io::outbuf_write(out, "Cast\n");
        write_labeled_child(out, indent + 1, "type", e.target_type, it);
        write_labeled_child(out, indent + 1, "expr", e.expr, it);
    }
    case ast::AstKind::UnaryOp: {
        ast::UnaryOpNode* e = (ast::UnaryOpNode*)n;
        io::outbuf_write(out, "UnaryOp ");
        io::outbuf_write(out, token::kind_name(e.op));
        io::outbuf_write_byte(out, '\n');
        print(e.operand, it, indent + 1, out);
    }
    case ast::AstKind::BinaryOp: {
        ast::BinaryOpNode* e = (ast::BinaryOpNode*)n;
        io::outbuf_write(out, "BinaryOp ");
        io::outbuf_write(out, token::kind_name(e.op));
        io::outbuf_write_byte(out, '\n');
        print(e.lhs, it, indent + 1, out);
        print(e.rhs, it, indent + 1, out);
    }
    case ast::AstKind::StructLit: {
        ast::StructLitNode* e = (ast::StructLitNode*)n;
        io::outbuf_write(out, "StructLit\n");
        write_field_inits(out, indent + 1, e.inits, it);
    }
    case ast::AstKind::ArrayLit: {
        ast::ArrayLitNode* e = (ast::ArrayLitNode*)n;
        io::outbuf_write(out, "ArrayLit\n");
        write_children(out, indent + 1, e.elems, it);
    }
    case ast::AstKind::Sizeof: {
        ast::SizeofNode* e = (ast::SizeofNode*)n;
        io::outbuf_write(out, "Sizeof\n");
        print(e.arg, it, indent + 1, out);
    }
    case ast::AstKind::Alignof: {
        ast::AlignofNode* e = (ast::AlignofNode*)n;
        io::outbuf_write(out, "Alignof\n");
        print(e.arg, it, indent + 1, out);
    }
    case ast::AstKind::Typeof: {
        ast::TypeofNode* e = (ast::TypeofNode*)n;
        io::outbuf_write(out, "Typeof\n");
        print(e.expr, it, indent + 1, out);
    }
    case ast::AstKind::Type_info: {
        ast::TypeInfoNode* e = (ast::TypeInfoNode*)n;
        io::outbuf_write(out, "TypeInfo\n");
        print(e.arg, it, indent + 1, out);
    }
    case ast::AstKind::Compcode: {
        ast::CompCodeNode* e = (ast::CompCodeNode*)n;
        io::outbuf_write(out, "CompCode\n");
        print(e.body, it, indent + 1, out);
    }

    // type expressions ///////////////////////////////////////////////////////
    case ast::AstKind::PrimitiveType: {
        ast::TypePrimitiveNode* t = (ast::TypePrimitiveNode*)n;
        io::outbuf_write(out, "PrimitiveType ");
        io::outbuf_write(out, token::kind_name(t.kind));
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::NamedType: {
        ast::TypeNamedNode* t = (ast::TypeNamedNode*)n;
        io::outbuf_write(out, "NamedType ");
        if(t.namespace) {
            write_sym(out, t.namespace, it);
            io::outbuf_write(out, "::");
        }
        write_sym(out, t.name, it);
        io::outbuf_write_byte(out, '\n');
    }
    case ast::AstKind::PointerType: {
        ast::TypePointerNode* t = (ast::TypePointerNode*)n;
        io::outbuf_write(out, "PointerType");
        if(t.is_const) { io::outbuf_write(out, " const"); }
        io::outbuf_write_byte(out, '\n');
        print(t.pointee, it, indent + 1, out);
    }
    case ast::AstKind::ArrayType: {
        ast::TypeArrayNode* t = (ast::TypeArrayNode*)n;
        io::outbuf_write(out, "ArrayType\n");
        write_labeled_child(out, indent + 1, "element", t.element, it);
        write_labeled_child(out, indent + 1, "size", t.size_expr, it);
    }
    case ast::AstKind::SliceType: {
        ast::TypeSliceNode* t = (ast::TypeSliceNode*)n;
        io::outbuf_write(out, "SliceType\n");
        print(t.element, it, indent + 1, out);
    }
    case ast::AstKind::FnPtrType: {
        ast::TypeFnPtrNode* t = (ast::TypeFnPtrNode*)n;
        io::outbuf_write(out, "FnPtrType\n");
        write_labeled_child(out, indent + 1, "return", t.return_type, it);
        write_indent(out, indent + 1);
        io::outbuf_write(out, "params\n");
        write_children(out, indent + 2, t.param_types, it);
    }
    case ast::AstKind::StructType: {
        ast::TypeStructNode* t = (ast::TypeStructNode*)n;
        io::outbuf_write(out, "StructType\n");
        write_fields(out, indent + 1, t.fields, it);
    }
    case ast::AstKind::UnionType: {
        ast::TypeUnionNode* t = (ast::TypeUnionNode*)n;
        io::outbuf_write(out, "UnionType\n");
        write_fields(out, indent + 1, t.fields, it);
    }

    else {
        io::outbuf_write(out, "<unknown kind ");
        io::outbuf_write_u64(out, (u64)n.h.kind);
        io::outbuf_write(out, ">\n");
    }
    }
}

// PRIVATE //////////////////////////////////////////////////////////////////

fn void write_indent(io::OutBuf* out, i32 indent) {
    for(i32 i = 0; i < indent; i += 1) {
        io::outbuf_write(out, "  ");
    }
}

fn void write_sym(io::OutBuf* out, symbol::Symbol* s, interner::Interner* it) {
    if(!s) { io::outbuf_write(out, "<null>"); return; }
    u8[] bytes = interner::symbol_str(s, it);
    io::outbuf_write(out, bytes);
}

fn void write_ns_chain(io::OutBuf* out, ast::AstNode* n, interner::Interner* it) {
    if(!n) { io::outbuf_write(out, "<null>"); return; }
    if(n.h.kind == ast::AstKind::NamespaceAccess) {
        ast::NamespaceAccessNode* na = (ast::NamespaceAccessNode*)n;
        write_ns_chain(out, na.base, it);
        io::outbuf_write(out, "::");
        write_sym(out, na.name, it);
        return;
    }
    if(n.h.kind == ast::AstKind::Ident) {
        ast::IdentNode* id = (ast::IdentNode*)n;
        write_sym(out, id.name, it);
        return;
    }
    io::outbuf_write(out, "<bad-ns-base>");
}

fn void write_labeled_child(io::OutBuf* out, i32 indent, u8[] label, ast::AstNode* child, interner::Interner* it) {
    write_indent(out, indent);
    io::outbuf_write(out, label);
    if(!child) {
        io::outbuf_write(out, ": <null>\n");
        return;
    }
    io::outbuf_write_byte(out, ':');
    io::outbuf_write_byte(out, '\n');
    print(child, it, indent + 1, out);
}

fn void write_children(io::OutBuf* out, i32 indent, ast::AstNode*[] list, interner::Interner* it) {
    for(u64 i = 0; i < list.len; i += 1) {
        print(list[i], it, indent, out);
    }
}

fn void write_params(io::OutBuf* out, i32 indent, ast::Param[] params, interner::Interner* it) {
    for(u64 i = 0; i < params.len; i += 1) {
        write_indent(out, indent);
        io::outbuf_write(out, "Param ");
        write_sym(out, params[i].name, it);
        if(params[i].is_const) { io::outbuf_write(out, " const"); }
        if(params[i].is_comptime) { io::outbuf_write(out, " comptime"); }
        io::outbuf_write_byte(out, '\n');
        print(params[i].type_expr, it, indent + 1, out);
    }
}

fn void write_fields(io::OutBuf* out, i32 indent, ast::FieldDecl[] fields, interner::Interner* it) {
    for(u64 i = 0; i < fields.len; i += 1) {
        write_indent(out, indent);
        io::outbuf_write(out, "Field ");
        write_sym(out, fields[i].name, it);
        io::outbuf_write_byte(out, '\n');
        print(fields[i].type_expr, it, indent + 1, out);
    }
}

fn void write_enum_members(io::OutBuf* out, i32 indent, ast::EnumMember[] members, interner::Interner* it) {
    for(u64 i = 0; i < members.len; i += 1) {
        write_indent(out, indent);
        io::outbuf_write(out, "Member ");
        write_sym(out, members[i].name, it);
        io::outbuf_write_byte(out, '\n');
        if(members[i].value_expr) {
            print(members[i].value_expr, it, indent + 1, out);
        }
    }
}

fn void write_field_inits(io::OutBuf* out, i32 indent, ast::FieldInitializer[] inits, interner::Interner* it) {
    for(u64 i = 0; i < inits.len; i += 1) {
        write_indent(out, indent);
        if(inits[i].name) {
            io::outbuf_write(out, ".");
            write_sym(out, inits[i].name, it);
            io::outbuf_write_byte(out, '\n');
        } else {
            io::outbuf_write(out, "positional\n");
        }
        print(inits[i].value, it, indent + 1, out);
    }
}

fn void write_switch_arms(io::OutBuf* out, i32 indent, ast::SwitchArm[] arms, interner::Interner* it) {
    for(u64 i = 0; i < arms.len; i += 1) {
        write_indent(out, indent);
        io::outbuf_write(out, "Arm\n");
        write_indent(out, indent + 1);
        io::outbuf_write(out, "labels\n");
        write_children(out, indent + 2, arms[i].labels, it);
        if(arms[i].body) {
            write_labeled_child(out, indent + 1, "body", arms[i].body, it);
        }
    }
}

fn void write_f64(io::OutBuf* out, f64 v) {
    u8[64] scratch;
    i32 n = sys::snprintf((i8*)&scratch[0], 64, "%g", v);
    if(n <= 0) { return; }
    u8[] tail = {&scratch[0], (u64)n};
    io::outbuf_write(out, tail);
}
