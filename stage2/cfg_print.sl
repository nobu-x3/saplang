import cfg;
import ast;
import ast_print;
import module;
import interner;
import symbol;
import io;

fn void write_sym(io::OutBuf* out, symbol::Symbol* s) {
    if(!s) { io::outbuf_write(out, "<null>"); return; }
    io::outbuf_write(out, interner::symbol_str(s));
}

fn void write_role(io::OutBuf* out, cfg::Cfg* g, cfg::BasicBlock* block) {
    if(block.id == g.entry) { io::outbuf_write(out, " (entry)"); return; }
    if(block.id == g.exit) { io::outbuf_write(out, " (exit)"); return; }
    if((u32)block.term.kind == (u32)cfg::TermKind::Unreachable) { io::outbuf_write(out, " (unreachable)"); }
}

fn void write_terminator(io::OutBuf* out, cfg::Terminator* t) {
    u32 kind = (u32)t.kind;
    if(kind == (u32)cfg::TermKind::Goto) {
        io::outbuf_write(out, "goto bb");
        io::outbuf_write_u64(out, (u64)t.goto_target);
    } else if(kind == (u32)cfg::TermKind::CondBranch) {
        io::outbuf_write(out, "cond bb");
        io::outbuf_write_u64(out, (u64)t.then_target);
        io::outbuf_write(out, " bb");
        io::outbuf_write_u64(out, (u64)t.else_target);
    } else if(kind == (u32)cfg::TermKind::Switch) {
        io::outbuf_write(out, "switch default bb");
        io::outbuf_write_u64(out, (u64)t.switch_default);
        for(u64 arm_index = 0; arm_index < t.switch_arms.len; arm_index += 1) {
            io::outbuf_write(out, " bb");
            io::outbuf_write_u64(out, (u64)t.switch_arms[arm_index].target);
        }
    } else if(kind == (u32)cfg::TermKind::Return) {
        io::outbuf_write(out, "return");
    } else {
        io::outbuf_write(out, "unreachable");
    }
}

export fn void print_cfg(cfg::Cfg* g, io::OutBuf* out) {
    for(u64 block_index = 0; block_index < g.blocks.len; block_index += 1) {
        cfg::BasicBlock* block = &g.blocks[block_index];
        io::outbuf_write(out, "  bb");
        io::outbuf_write_u64(out, (u64)block.id);
        write_role(out, g, block);
        io::outbuf_write(out, ":\n");
        for(u64 stmt_index = 0; stmt_index < block.stmts.len; stmt_index += 1) {
            ast_print::print(block.stmts[stmt_index], 2, out);
        }
        io::outbuf_write(out, "    -> ");
        write_terminator(out, &block.term);
        io::outbuf_write_byte(out, '\n');
    }
}

export fn void print_fn(ast::FnDeclNode* func, io::OutBuf* out) {
    io::outbuf_write(out, "fn ");
    write_sym(out, func.name);
    io::outbuf_write(out, ":\n");
    cfg::Cfg* g = (cfg::Cfg*)func.cfg;
    if(g == null) {
        io::outbuf_write(out, "  <no cfg>\n");
        return;
    }
    print_cfg(g, out);
}

export fn void print_module(module::Module* m, io::OutBuf* out) {
    if(m.root_node == null) { return; }
    ast::BlockNode* global_block = (ast::BlockNode*)m.root_node;
    for(u64 stmt_index = 0; stmt_index < global_block.stmts.len; stmt_index += 1) {
        ast::AstNode* node = global_block.stmts[stmt_index];
        if(node.h.kind != ast::AstKind::FnDecl) { continue; }
        ast::FnDeclNode* func = (ast::FnDeclNode*)node;
        if(func.cfg == null) { continue; }
        print_fn(func, out);
    }
}
