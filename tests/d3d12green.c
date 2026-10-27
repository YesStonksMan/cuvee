// SPDX-License-Identifier: LGPL-2.1-or-later
// Minimal D3D12 window: clears the back buffer to green for 20 s, prints each step's HRESULT.
#define COBJMACROS
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <stdio.h>
#define CHECK(what, call) do { HRESULT hr_ = (call); printf("%s hr=%08lx\n", what, (unsigned long)hr_); fflush(stdout); if (FAILED(hr_)) return 1; } while (0)
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l){ if(m==WM_DESTROY){PostQuitMessage(0);return 0;} return DefWindowProcA(h,m,w,l); }
int main(void){
  WNDCLASSA wc={0}; wc.lpfnWndProc=wp; wc.hInstance=GetModuleHandleA(0); wc.lpszClassName="d3d12green"; RegisterClassA(&wc);
  HWND hw=CreateWindowA("d3d12green","D3D12 GREEN",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,640,480,0,0,wc.hInstance,0);
  ID3D12Device *dev; IDXGIFactory4 *f; ID3D12CommandQueue *q; IDXGISwapChain1 *sc1; IDXGISwapChain3 *sc;
  ID3D12DescriptorHeap *heap; ID3D12Resource *bb[2]; ID3D12CommandAllocator *ca; ID3D12GraphicsCommandList *cl; ID3D12Fence *fence;
  CHECK("D3D12CreateDevice", D3D12CreateDevice(0, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void**)&dev));
  CHECK("CreateDXGIFactory2", CreateDXGIFactory2(0, &IID_IDXGIFactory4, (void**)&f));
  D3D12_COMMAND_QUEUE_DESC qd={0}; qd.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;
  CHECK("CreateCommandQueue", ID3D12Device_CreateCommandQueue(dev, &qd, &IID_ID3D12CommandQueue, (void**)&q));
  DXGI_SWAP_CHAIN_DESC1 sd={0}; sd.Width=640; sd.Height=480; sd.Format=DXGI_FORMAT_R8G8B8A8_UNORM; sd.SampleDesc.Count=1;
  sd.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount=2; sd.SwapEffect=DXGI_SWAP_EFFECT_FLIP_DISCARD;
  CHECK("CreateSwapChainForHwnd", IDXGIFactory4_CreateSwapChainForHwnd(f, (IUnknown*)q, hw, &sd, 0, 0, &sc1));
  CHECK("QueryInterface swapchain3", IDXGISwapChain1_QueryInterface(sc1, &IID_IDXGISwapChain3, (void**)&sc));
  D3D12_DESCRIPTOR_HEAP_DESC hd={0}; hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV; hd.NumDescriptors=2;
  CHECK("CreateDescriptorHeap", ID3D12Device_CreateDescriptorHeap(dev, &hd, &IID_ID3D12DescriptorHeap, (void**)&heap));
  UINT inc=ID3D12Device_GetDescriptorHandleIncrementSize(dev, D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
  D3D12_CPU_DESCRIPTOR_HANDLE base; heap->lpVtbl->GetCPUDescriptorHandleForHeapStart(heap, &base);
  for(int i=0;i<2;i++){
    CHECK("GetBuffer", IDXGISwapChain3_GetBuffer(sc, i, &IID_ID3D12Resource, (void**)&bb[i]));
    D3D12_CPU_DESCRIPTOR_HANDLE h={base.ptr+i*inc}; ID3D12Device_CreateRenderTargetView(dev, bb[i], 0, h);
  }
  CHECK("CreateCommandAllocator", ID3D12Device_CreateCommandAllocator(dev, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void**)&ca));
  CHECK("CreateCommandList", ID3D12Device_CreateCommandList(dev, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, ca, 0, &IID_ID3D12GraphicsCommandList, (void**)&cl));
  CHECK("Close", ID3D12GraphicsCommandList_Close(cl));
  CHECK("CreateFence", ID3D12Device_CreateFence(dev, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void**)&fence));
  HANDLE ev=CreateEventA(0,FALSE,FALSE,0); UINT64 fv=0; float green[4]={0,1,0,1}; DWORD t=GetTickCount(); HRESULT hr=S_OK; MSG msg; int frames=0;
  while(GetTickCount()-t<20000){
    while(PeekMessageA(&msg,0,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageA(&msg);}
    UINT i=IDXGISwapChain3_GetCurrentBackBufferIndex(sc); D3D12_CPU_DESCRIPTOR_HANDLE h={base.ptr+i*inc};
    ID3D12CommandAllocator_Reset(ca); ID3D12GraphicsCommandList_Reset(cl, ca, 0);
    D3D12_RESOURCE_BARRIER b={0}; b.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION; b.Transition.pResource=bb[i];
    b.Transition.Subresource=D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES; b.Transition.StateBefore=D3D12_RESOURCE_STATE_PRESENT; b.Transition.StateAfter=D3D12_RESOURCE_STATE_RENDER_TARGET;
    ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &b);
    ID3D12GraphicsCommandList_ClearRenderTargetView(cl, h, green, 0, 0);
    b.Transition.StateBefore=D3D12_RESOURCE_STATE_RENDER_TARGET; b.Transition.StateAfter=D3D12_RESOURCE_STATE_PRESENT;
    ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &b);
    ID3D12GraphicsCommandList_Close(cl);
    ID3D12CommandQueue_ExecuteCommandLists(q, 1, (ID3D12CommandList**)&cl);
    hr=IDXGISwapChain3_Present(sc, 1, 0); if(FAILED(hr)) break;
    ID3D12CommandQueue_Signal(q, fence, ++fv); ID3D12Fence_SetEventOnCompletion(fence, fv, ev); WaitForSingleObject(ev, 1000);
    frames++;
  }
  printf("present hr=%08lx frames=%d\n", (unsigned long)hr, frames); fflush(stdout); return FAILED(hr);
}
