// SPDX-License-Identifier: LGPL-2.1-or-later
// D3D12 triangle: compiles HLSL at runtime (d3dcompiler_47), builds a root signature + pipeline, draws a
// red/green/blue triangle on a dark background for 20 s. Exercises the shader path that d3d12green.c skips.
#define COBJMACROS
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <d3dcompiler.h>
#include <stdio.h>
#include <string.h>
#define CHECK(what, call) do { HRESULT hr_ = (call); printf("%s hr=%08lx\n", what, (unsigned long)hr_); fflush(stdout); if (FAILED(hr_)) return 1; } while (0)
static const char hlsl[] =
  "struct V { float4 p : SV_Position; float4 c : COLOR; };\n"
  "V vs(uint id : SV_VertexID) { V o; float2 p[3] = { float2(0, .7), float2(.7, -.7), float2(-.7, -.7) };\n"
  "  float4 c[3] = { float4(1,0,0,1), float4(0,1,0,1), float4(0,0,1,1) }; o.p = float4(p[id], 0, 1); o.c = c[id]; return o; }\n"
  "float4 ps(V i) : SV_Target { return i.c; }\n";
static LRESULT CALLBACK wp(HWND h, UINT m, WPARAM w, LPARAM l){ if(m==WM_DESTROY){PostQuitMessage(0);return 0;} return DefWindowProcA(h,m,w,l); }
static int compile(const char *entry, const char *target, ID3DBlob **out){
  ID3DBlob *err = 0; HRESULT hr = D3DCompile(hlsl, strlen(hlsl), 0, 0, 0, entry, target, 0, 0, out, &err);
  printf("D3DCompile %s hr=%08lx %s\n", entry, (unsigned long)hr, err ? (char*)ID3D10Blob_GetBufferPointer(err) : ""); fflush(stdout);
  return SUCCEEDED(hr);
}
int main(void){
  WNDCLASSA wc={0}; wc.lpfnWndProc=wp; wc.hInstance=GetModuleHandleA(0); wc.lpszClassName="d3d12tri"; RegisterClassA(&wc);
  HWND hw=CreateWindowA("d3d12tri","D3D12 TRIANGLE",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,640,480,0,0,wc.hInstance,0);
  ID3D12Device *dev; IDXGIFactory4 *f; ID3D12CommandQueue *q; IDXGISwapChain1 *sc1; IDXGISwapChain3 *sc; ID3D12DescriptorHeap *heap;
  ID3D12Resource *bb[2]; ID3D12CommandAllocator *ca; ID3D12GraphicsCommandList *cl; ID3D12Fence *fence;
  ID3D12RootSignature *rs; ID3D12PipelineState *pso; ID3DBlob *vsb, *psb, *rsb, *err;
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
  D3D12_ROOT_SIGNATURE_DESC rsd={0};
  CHECK("D3D12SerializeRootSignature", D3D12SerializeRootSignature(&rsd, D3D_ROOT_SIGNATURE_VERSION_1, &rsb, &err));
  CHECK("CreateRootSignature", ID3D12Device_CreateRootSignature(dev, 0, ID3D10Blob_GetBufferPointer(rsb), ID3D10Blob_GetBufferSize(rsb), &IID_ID3D12RootSignature, (void**)&rs));
  if(!compile("vs", "vs_5_0", &vsb) || !compile("ps", "ps_5_0", &psb)) return 1;
  D3D12_GRAPHICS_PIPELINE_STATE_DESC pd={0}; pd.pRootSignature=rs;
  pd.VS.pShaderBytecode=ID3D10Blob_GetBufferPointer(vsb); pd.VS.BytecodeLength=ID3D10Blob_GetBufferSize(vsb);
  pd.PS.pShaderBytecode=ID3D10Blob_GetBufferPointer(psb); pd.PS.BytecodeLength=ID3D10Blob_GetBufferSize(psb);
  pd.BlendState.RenderTarget[0].RenderTargetWriteMask=D3D12_COLOR_WRITE_ENABLE_ALL; pd.SampleMask=UINT_MAX;
  pd.RasterizerState.FillMode=D3D12_FILL_MODE_SOLID; pd.RasterizerState.CullMode=D3D12_CULL_MODE_NONE; pd.RasterizerState.DepthClipEnable=TRUE;
  pd.PrimitiveTopologyType=D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE; pd.NumRenderTargets=1; pd.RTVFormats[0]=DXGI_FORMAT_R8G8B8A8_UNORM; pd.SampleDesc.Count=1;
  CHECK("CreateGraphicsPipelineState", ID3D12Device_CreateGraphicsPipelineState(dev, &pd, &IID_ID3D12PipelineState, (void**)&pso));
  CHECK("CreateCommandAllocator", ID3D12Device_CreateCommandAllocator(dev, D3D12_COMMAND_LIST_TYPE_DIRECT, &IID_ID3D12CommandAllocator, (void**)&ca));
  CHECK("CreateCommandList", ID3D12Device_CreateCommandList(dev, 0, D3D12_COMMAND_LIST_TYPE_DIRECT, ca, 0, &IID_ID3D12GraphicsCommandList, (void**)&cl));
  CHECK("Close", ID3D12GraphicsCommandList_Close(cl));
  CHECK("CreateFence", ID3D12Device_CreateFence(dev, 0, D3D12_FENCE_FLAG_NONE, &IID_ID3D12Fence, (void**)&fence));
  HANDLE ev=CreateEventA(0,FALSE,FALSE,0); UINT64 fv=0; float bg[4]={.1f,.1f,.12f,1}; DWORD t=GetTickCount(); HRESULT hr=S_OK; MSG msg; int frames=0;
  D3D12_VIEWPORT vp={0,0,640,480,0,1}; D3D12_RECT sr={0,0,640,480};
  while(GetTickCount()-t<20000){
    while(PeekMessageA(&msg,0,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageA(&msg);}
    UINT i=IDXGISwapChain3_GetCurrentBackBufferIndex(sc); D3D12_CPU_DESCRIPTOR_HANDLE h={base.ptr+i*inc};
    ID3D12CommandAllocator_Reset(ca); ID3D12GraphicsCommandList_Reset(cl, ca, pso);
    D3D12_RESOURCE_BARRIER b={0}; b.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION; b.Transition.pResource=bb[i];
    b.Transition.Subresource=D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES; b.Transition.StateBefore=D3D12_RESOURCE_STATE_PRESENT; b.Transition.StateAfter=D3D12_RESOURCE_STATE_RENDER_TARGET;
    ID3D12GraphicsCommandList_ResourceBarrier(cl, 1, &b);
    ID3D12GraphicsCommandList_ClearRenderTargetView(cl, h, bg, 0, 0);
    ID3D12GraphicsCommandList_SetGraphicsRootSignature(cl, rs);
    ID3D12GraphicsCommandList_RSSetViewports(cl, 1, &vp); ID3D12GraphicsCommandList_RSSetScissorRects(cl, 1, &sr);
    ID3D12GraphicsCommandList_OMSetRenderTargets(cl, 1, &h, FALSE, 0);
    ID3D12GraphicsCommandList_IASetPrimitiveTopology(cl, D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    ID3D12GraphicsCommandList_DrawInstanced(cl, 3, 1, 0, 0);
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
