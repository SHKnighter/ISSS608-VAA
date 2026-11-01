"""Local masked key entry and download status; no secret is persisted."""
import contextlib
import importlib.util
from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import ttk

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ex03_ridership_backend',ROOT/'R/acquire-ridership.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class QueueOutput:
    def __init__(self,events,key): self.events,self.key=events,key
    def write(self,text):
        if text: self.events.put(('log',text.replace(self.key,'[hidden]')))
        return len(text)
    def flush(self): pass


def perform_download(key,root,events,acquire_fn=None):
    key=key.strip()
    if not key:
        events.put(('error','请先粘贴 DataMall API Access Key。'))
        return
    if not key.isascii() or any(c.isspace() for c in key):
        events.put(('error','输入包含空格、换行或非英文字符，请只复制邮件中的密钥。'))
        return
    try:
        stream=QueueOutput(events,key)
        with contextlib.redirect_stdout(stream),contextlib.redirect_stderr(stream):
            (backend.acquire if acquire_fn is None else acquire_fn)(Path(root),key)
        events.put(('done','下载完成。请回到作业聊天，告诉我“客流已下载”。'))
    except backend.AcquisitionError as error:
        events.put(('error',str(error).replace(key,'[hidden]')))
    except Exception:
        events.put(('error','下载遇到未识别问题。请提供本窗口中的状态消息；密钥不会显示。'))
    finally:
        key=None


class DownloadWindow:
    def __init__(self,window,root=ROOT):
        self.window,self.root=window,Path(root)
        self.events=queue.Queue(); self.busy=False; self.completed=False
        window.title('LTA 客流数据下载')
        window.geometry('780x520'); window.minsize(680,450)
        frame=ttk.Frame(window,padding=20); frame.pack(fill='both',expand=True)
        ttk.Label(frame,text='输入 DataMall API 访问密钥',font=('Microsoft YaHei UI',15,'bold')).pack(anchor='w')
        ttk.Label(frame,text='请找 DataMall API Access Key 邮件。Your SDK Account Key 是另一种用途。',
                  wraplength=720).pack(anchor='w',pady=(10,14))
        self.key=tk.StringVar()
        self.entry=ttk.Entry(frame,textvariable=self.key,show='*',font=('Consolas',13))
        self.entry.pack(fill='x')
        self.count=tk.StringVar(value='已输入 0 个字符。支持 Ctrl+V 粘贴，内容以星号显示。')
        ttk.Label(frame,textvariable=self.count).pack(anchor='w',pady=(5,12))
        self.key.trace_add('write',self._count_changed)
        self.button=ttk.Button(frame,text='开始下载 2026 年 8 月、9 月客流',command=self.start)
        self.button.pack(anchor='w',pady=(0,12))
        self.status=tk.StringVar(value='等待输入。密钥只在本次程序内使用，不写入项目文件。')
        ttk.Label(frame,textvariable=self.status,wraplength=720).pack(anchor='w',pady=(0,8))
        self.log=tk.Text(frame,height=12,wrap='word',font=('Microsoft YaHei UI',10),state='disabled')
        self.log.pack(fill='both',expand=True)
        self.entry.bind('<Return>',lambda event:self.start())
        self.entry.focus_set()
        window.after(120,self.consume_events)

    def _count_changed(self,*args):
        self.count.set(f'已输入 {len(self.key.get())} 个字符，内容已隐藏。')

    def start(self):
        if self.busy: return
        key=self.key.get().strip()
        if not key:
            self.status.set('请先粘贴 API 密钥，再点击开始下载。'); return
        self.busy=True; self.completed=False
        self.key.set(''); self.entry.configure(state='disabled'); self.button.configure(state='disabled')
        self.status.set('已收到输入，正在连接 LTA。下方将显示当前步骤和具体错误。')
        self.log.configure(state='normal'); self.log.delete('1.0','end'); self.log.configure(state='disabled')
        threading.Thread(target=perform_download,args=(key,self.root,self.events),daemon=True).start()

    def consume_events(self):
        try:
            while True:
                kind,message=self.events.get_nowait()
                self.log.configure(state='normal')
                self.log.insert('end',message if kind=='log' else '\n'+message+'\n')
                self.log.see('end'); self.log.configure(state='disabled')
                if kind in ('done','error'):
                    self.busy=False
                    self.completed=(kind=='done')
                    self.entry.configure(state='normal'); self.button.configure(state='normal')
                    if kind=='done': self.status.set(message)
                    elif '401' in message: self.status.set('身份验证未通过。请核对 API 邮件中的密钥；SDK 密钥另作他用。')
                    elif '403' in message: self.status.set('LTA 拒绝访问。请保留下方状态，供进一步核查。')
                    else: self.status.set('未完成下载。下方有具体原因，可截图反馈；窗口内不会显示密钥。')
        except queue.Empty:
            pass
        self.window.after(120,self.consume_events)


def main():
    window=tk.Tk(); app=DownloadWindow(window); window.mainloop()
    return 0 if app.completed else 1


if __name__=='__main__': raise SystemExit(main())
