// SPDX-License-Identifier: LGPL-2.1-or-later
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l){ if(m==WM_DESTROY){PostQuitMessage(0);return 0;} return DefWindowProcA(h,m,w,l); }
int main(void){
  WNDCLASSA wc={0}; wc.lpfnWndProc=wp; wc.hInstance=GetModuleHandleA(0); wc.lpszClassName="d3dred"; RegisterClassA(&wc);
  HWND hw=CreateWindowA("d3dred","D3D11 RED",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,640,480,0,0,wc.hInstance,0);
  DXGI_SWAP_CHAIN_DESC sd={0}; sd.BufferCount=2; sd.BufferDesc.Width=640; sd.BufferDesc.Height=480; sd.BufferDesc.Format=DXGI_FORMAT_R8G8B8A8_UNORM;
  sd.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.OutputWindow=hw; sd.SampleDesc.Count=1; sd.Windowed=TRUE; sd.SwapEffect=DXGI_SWAP_EFFECT_FLIP_DISCARD;
  IDXGISwapChain *sc; ID3D11Device *dev; ID3D11DeviceContext *ctx;
  HRESULT hr=D3D11CreateDeviceAndSwapChain(0,D3D_DRIVER_TYPE_HARDWARE,0,0,0,0,D3D11_SDK_VERSION,&sd,&sc,&dev,0,&ctx);
  printf("create hr=%08lx\n",hr); fflush(stdout); if(FAILED(hr)) return 1;
  ID3D11Texture2D *bb; IDXGISwapChain_GetBuffer(sc,0,&IID_ID3D11Texture2D,(void**)&bb);
  ID3D11RenderTargetView *rtv; ID3D11Device_CreateRenderTargetView(dev,(ID3D11Resource*)bb,0,&rtv);
  float red[4]={1,0,0,1}; DWORD t=GetTickCount();
  MSG msg; while(GetTickCount()-t<20000){ while(PeekMessageA(&msg,0,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageA(&msg);}
    ID3D11DeviceContext_OMSetRenderTargets(ctx,1,&rtv,0); ID3D11DeviceContext_ClearRenderTargetView(ctx,rtv,red);
    hr=IDXGISwapChain_Present(sc,1,0); Sleep(16);} printf("present hr=%08lx\n",hr); return 0; }
