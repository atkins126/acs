(*
FLAC (Free Lossless Audio Codec) components

This file is a part of Audio Components Suite.
All rights reserved. See the license file for more details.

Copyright (c) 2002-2009, Andrei Borovsky, anb@symmetrica.net
Copyright (c) 2005-2006  Christian Ulrich, mail@z0m3ie.de
Copyright (c) 2014-2015  Sergey Bodrov, serbod@gmail.com
*)

unit acs_flac;

interface

uses

 ACS_File, Classes, SysUtils, ACS_Types, ACS_Classes, FLAC,
{$IFDEF LINUX}
  baseunix;
{$ENDIF}

{$IFDEF WIN32}
  Windows;
{$ENDIF}

type

  TFLACOut = class(TAcsCustomFileOut)
  private
    _encoder: PFLAC__SeekableStreamEncoder;
    FVerify: Boolean;
    FBlockSize: Word;
    FBestModelSearch: Boolean;
    FEnableMidSideStereo: Boolean;
    FMaxLPCOrder: Word;
    EndOfInput: Boolean;
    FEnableLooseMidSideStereo: Boolean;
    FQLPCoeffPrecision: Word;
    FQLPCoeffPrecisionSearch: Boolean;
    FMaxResidualPartitionOrder: Word;
    FMinResidualPartitionOrder: Word;
    procedure SetEnableLooseMidSideStereo(val: Boolean);
    procedure SetBestModelSearch(val: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy(); override;
    procedure Prepare(); override;
    procedure Done(); override;
    function DoOutput(Abort: Boolean):Boolean; override;
  published
    property BestModelSearch: Boolean read FBestModelSearch write SetBestModelSearch;
    property BlockSize: Word read FBlockSize write FBlockSize;
    property EnableMidSideStereo: Boolean read FEnableMidSideStereo write FEnableMidSideStereo;
    property EnableLooseMidSideStereo: Boolean read FEnableLooseMidSideStereo write SetEnableLooseMidSideStereo;
    property MaxLPCOrder: Word read FMaxLPCOrder write FMaxLPCOrder;
    property MaxResidualPartitionOrder: Word read FMaxResidualPartitionOrder write FMaxResidualPartitionOrder;
    property MinResidualPartitionOrder: Word read FMinResidualPartitionOrder write FMinResidualPartitionOrder;
    property QLPCoeffPrecision: Word read FQLPCoeffPrecision write FQLPCoeffPrecision;
    property QLPCoeffPrecisionSearch: Boolean read FQLPCoeffPrecisionSearch write FQLPCoeffPrecisionSearch;
    property Verify: Boolean read FVerify write FVerify;
  end;

  TFLACIn = class(TAcsCustomFileIn)
  private
    Buff: PAcsBuffer8;
    _decoder: PFLAC__SeekableStreamDecoder;
    FBlockSize: Integer;
    BytesPerBlock: Integer;
    EndOfStream: Boolean;
    MinFrameSize: Integer;
  protected
    procedure OpenFile; override;
    procedure CloseFile; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetData(Buffer: Pointer; BufferSize: Integer): Integer; override;
    function Seek(SampleNum: Integer): Boolean; override;
  end;


implementation

const
  DEFAULT_BUFFER_SIZE = $6000;

type

  FLACBuf = array[0..0] of FLAC__int32;
  PFLACBuf = ^FLACBuf;

function EncWriteCBFunc(encoder: PFLAC__SeekableStreamEncoder;
                        buffer: PFLAC__byte;
                        bytes, samples, current_frame: LongWord;
                        client_data: Pointer): Integer; cdecl;
var
  FLACOut: TFLACOut;
begin
  FLACOut:=TFLACOut(client_data);
  Result:=FLAC__SEEKABLE_STREAM_ENCODER_OK;
  try
    FLACOut.FStream.Write(buffer^, bytes);
  except
    Result:=FLAC__SEEKABLE_STREAM_ENCODER_WRITE_ERROR;
  end;
end;

function EncSeekCBFunc(encoder: PFLAC__SeekableStreamEncoder;
                       absolute_byte_offset: FLAC__uint64;
                       client_data: Pointer): Integer; cdecl;
var
  FLACOut: TFLACOut;
begin
  FLACOut:=TFLACOut(client_data);
  Result:=FLAC__SEEKABLE_STREAM_ENCODER_SEEK_STATUS_OK;
  try
    FLACOut.FStream.Seek(absolute_byte_offset, soFromBeginning);
  except
    Result:=FLAC__SEEKABLE_STREAM_ENCODER_SEEK_ERROR;
  end;
end;

function DecReadCBFunc(decoder: PFLAC__SeekableStreamDecoder;
                       buffer: PFLAC__byte;
                       var bytes: LongWord;
                       client_data: Pointer): Integer; cdecl;
var
  FLACIn: TFLACIn;
begin
  FLACIn:=TFLACIn(client_data);
  Result:=FLAC__SEEKABLE_STREAM_DECODER_READ_STATUS_OK;
  if FLACIn.FStream.Position >= FLACIn.FStream.Size then
  begin
    Result:=FLAC__SEEKABLE_STREAM_DECODER_END_OF_STREAM;
    Exit;
  end;
  try
    bytes:=FLACIn.FStream.Read(buffer^, bytes);
  except
    Result:=FLAC__SEEKABLE_STREAM_DECODER_READ_ERROR;
  end;
end;

function DecSeekCBFunc(decoder: PFLAC__SeekableStreamDecoder;
                       absolute_byte_offset: FLAC__uint64;
                       client_data: Pointer): Integer; cdecl;
var
  FLACIn: TFLACIn;
begin
  FLACIn:=TFLACIn(client_data);
  Result:=FLAC__SEEKABLE_STREAM_DECODER_SEEK_STATUS_OK;
  try
    FLACIn.FStream.Seek(absolute_byte_offset, soFromBeginning);
  except
    Result:=FLAC__SEEKABLE_STREAM_DECODER_SEEK_STATUS_ERROR;
  end;
end;

function DecTellCBFunc(decoder: PFLAC__SeekableStreamDecoder;
                       var absolute_byte_offset: FLAC__uint64;
                       client_data: Pointer): Integer; cdecl;
var
  FLACIn: TFLACIn;
begin
  FLACIn:=TFLACIn(client_data);
  Result:=FLAC__SEEKABLE_STREAM_DECODER_TELL_STATUS_OK;
  try
    absolute_byte_offset:=FLACIn.FStream.Position;
  except
    Result:=FLAC__SEEKABLE_STREAM_DECODER_TELL_STATUS_ERROR;
  end;
end;

function DecLengthCBFunc(decoder: PFLAC__SeekableStreamDecoder;
                         var stream_length: FLAC__uint64;
                         client_data: Pointer): Integer; cdecl;
var
  FLACIn: TFLACIn;
begin
  FLACIn:=TFLACIn(client_data);
  Result:=FLAC__SEEKABLE_STREAM_DECODER_LENGTH_STATUS_OK;
  try
    stream_length:=FLACIn.FStream.Size;
  except
    Result:=FLAC__SEEKABLE_STREAM_DECODER_LENGTH_STATUS_ERROR;
  end;
end;

function DecEOFCBFunc(decoder: PFLAC__SeekableStreamDecoder;
                      client_data: Pointer): Boolean; cdecl;
var
  FLACIn: TFLACIn;
begin
  FLACIn:=TFLACIn(client_data);
  Result:=(FLACIn.FStream.Position >= FLACIn.FStream.Size);
end;

function DecWriteCBFunc(decoder: PFLAC__SeekableStreamDecoder;
                        frame: PFLAC__Frame;
                        buffer: PFLACChannels;
                        client_data: Pointer): Integer; cdecl;
var
  FLACIn: TFLACIn;
  Header: PFLAC__FrameHeader;
  buffer1: PFLACIntBuf;
  buffer2: PFLACIntBuf;
  B16: PAcsBuffer16;
  i: Integer;
begin
  FLACIn:=TFLACIn(client_data);
  Header:=PFLAC__FrameHeader(frame);
  FLACIn.FBlockSize:=Header.blocksize;
  FLACIn.BytesPerBlock:=FLACIn.FBlockSize * (FLACIn.FBPS shr 3) * FLACIn.FChan;
  GetMem(FLACIn.Buff, FLACIn.BytesPerBlock);
//  FillChar(FLACIn.Buff[0], FLACIn.BytesPerBlock, 255);
  if FLACIn.FBPS = 16 then
  begin
    B16:=PAcsBuffer16(FLACIn.Buff);
    if FLACIn.FChan = 1 then
    begin
     buffer1:=buffer[0];
     for i:=0 to FLACIn.FBlockSize-1 do
       B16[i]:=buffer1[i];
    end
    else
    begin
      buffer1:=buffer[0];
      buffer2:=buffer[1];
      for i:=0 to FLACIn.FBlockSize-1 do
      begin
        B16[i shl 1]:=buffer1[i];
        B16[(i shl 1)+1]:=buffer2[i];
      end;
    end;
  end
  else
  begin
    if FLACIn.FChan = 1 then
    begin
      buffer1:=buffer[0];
      for i:=0 to FLACIn.FBlockSize-1 do
        FLACIn.Buff[i]:=buffer1[i];
    end
    else
    begin
      buffer1:=buffer[0];
      buffer2:=buffer[1];
      for i:=0 to FLACIn.FBlockSize-1 do
      begin
        FLACIn.Buff[i shl 1]:=buffer1[i];
        FLACIn.Buff[(i shl 1)+1]:=buffer2[i];
      end;
    end;
  end;
  Result:=FLAC__SEEKABLE_STREAM_ENCODER_OK;
end;

procedure DecMetadataCBProc(decoder: PFLAC__SeekableStreamDecoder;
                            metadata: PFLAC__StreamMetadata;
                            client_data: Pointer); cdecl;
var
  FLACIn: TFLACIn;
  P: Pointer;
  FI: PFLACInfo;
begin
  if LongWord(metadata^) <> 0 then Exit;
  P:=metadata;
  (*
   STREAMINFO block format differs in different
   FLAC codec versions, so we are trying to be flexible here.
  *)
  while LongWord(P^) = 0 do Inc(P, 4);
  Inc(P, 4);
  if LongWord(P^) = 0 then Inc(P, 4);
  FI:=PFLACInfo(P);
  FLACIn:=TFLACIn(client_data);
  FLACIn.FSR:=FI.sample_rate;
  FLACIn.FChan:=FI.channels;
  if FLACIn.FChan > 2 then FLACIn.FValid:=False;
  FLACIn.FBPS:=FI.bits_per_sample;
  if FLACIn.FChan > 16 then FLACIn.FValid:=False;
  FLACIn.FTotalSamples:=FI.total_samples1;
  if FLACIn.FTotalSamples = 0 then
    FLACIn.FTotalSamples:=FI.total_samples2;
  FLACIn.FSize:=FLACIn.FTotalSamples * (FLACIn.FBPS div 8) * FLACIn.FChan;
  FLACIn.MinFrameSize:=FI.min_framesize;
end;

procedure DecErrorCBProc(decoder: PFLAC__SeekableStreamDecoder;
                         status: Integer;
                         client_data: Pointer); cdecl;
var
  FLACIn: TFLACIn;
begin
  FLACIn:=TFLACIn(client_data);
  FLACIn.FValid:=False;
end;

constructor TFLACOut.Create();
begin
  inherited Create(AOwner);
  FVerify:=False;
  FBufferSize:=DEFAULT_BUFFER_SIZE; // default buffer size
  FBlockSize:=4608;
  FBestModelSearch:=False;
  FEnableMidSideStereo:=True;
  if not (csDesigning in ComponentState) then
    if not LibFLACLoaded then
      raise EAcsException.Create(LibFLACPath + ' library could not be loaded.');
end;

destructor TFLACOut.Destroy();
begin
  inherited Destroy();
end;

procedure TFLACOut.Prepare();
begin
  // TODO: Recreate this stuff with buffersize more equal to default
  FBufferSize:=DEFAULT_BUFFER_SIZE div FBlockSize;
  FBufferSize:=FBufferSize * (FInput.BitsPerSample div 8) * FInput.Channels;
  inherited Prepare();

  EndOfInput:=False;
  _encoder:=FLAC__seekable_stream_encoder_new;
  if _encoder = nil then
    raise EAcsException.Create('Failed to initialize FLAC encoder.');
  FLAC__seekable_stream_encoder_set_verify(_encoder, FVerify);
  FLAC__seekable_stream_encoder_set_channels(_encoder, FInput.Channels);
  FLAC__seekable_stream_encoder_set_bits_per_sample(_encoder, FInput.BitsPerSample);
  FLAC__seekable_stream_encoder_set_sample_rate(_encoder, FInput.SampleRate);
  if FInput.Channels = 2 then
  begin
    FLAC__seekable_stream_encoder_set_do_mid_side_stereo(_encoder, FEnableMidSideStereo);
    FLAC__seekable_stream_encoder_set_loose_mid_side_stereo(_encoder, FEnableLooseMidSideStereo);
  end;
  FLAC__seekable_stream_encoder_set_blocksize(_encoder, FBlockSize);
  FLAC__seekable_stream_encoder_set_max_lpc_order(_encoder, FMaxLPCOrder);
  if FQLPCoeffPrecision + FInput.BitsPerSample > 31 then
    FQLPCoeffPrecision:=31 - FInput.BitsPerSample;
  FLAC__seekable_stream_encoder_set_qlp_coeff_precision(_encoder, FQLPCoeffPrecision);
  FLAC__seekable_stream_encoder_set_do_qlp_coeff_prec_search(_encoder, FQLPCoeffPrecisionSearch);
  FLAC__seekable_stream_encoder_set_min_residual_partition_order(_encoder, FMinResidualPartitionOrder);
  FLAC__seekable_stream_encoder_set_max_residual_partition_order(_encoder, FMaxResidualPartitionOrder);
  FLAC__seekable_stream_encoder_set_do_exhaustive_model_search(_encoder, FBestModelSearch);
  {if FInput.Size > 0 then
    FLAC__seekable_stream_encoder_set_total_samples_estimate(_encoder, Round(FInput.Size / (FInput.BitsPerSample div 8) / FInput.Channels)); }
  FLAC__seekable_stream_encoder_set_seek_callback(_encoder, EncSeekCBFunc);
  FLAC__seekable_stream_encoder_set_write_callback(_encoder, EncWriteCBFunc);
  FLAC__seekable_stream_encoder_set_client_data(_encoder, Self);
  if FLAC__seekable_stream_encoder_init(_encoder) <> FLAC__SEEKABLE_STREAM_ENCODER_OK then
  begin
    FInput.Done();
    raise EAcsException.Create('Failed to initialize FLAC encoder.');
  end;
end;

procedure TFLACOut.Done();
begin
  if Assigned(FStream) then
    FLAC__seekable_stream_encoder_finish(_encoder);
  FLAC__seekable_stream_encoder_delete(_encoder);
  inherited Done();
end;

function TFLACOut.DoOutput(Abort: Boolean):Boolean;
var
  Len, i, samples: Integer;
  FB: PFLACBuf;
  B16: PAcsBuffer16;
begin
  Result:=False;
  if not CanOutput then Exit;
  if Abort or EndOfInput then Exit;

  // get samples from input
  Len:=FillBufferFromInput(EndOfInput);
  if Len = 0 then Exit;

  samples:=(Len shl 3) div FInput.BitsPerSample;
  GetMem(FB, samples * SizeOF(FLAC__int32));
  try
    if FInput.BitsPerSample = 16 then
    begin
      //B16:=@FBuffer[0];
      B16:=FBuffer.Memory;
      for i:=0 to samples-1 do FB[i]:=B16[i];
    end;
    //else
      //for i:=0 to samples-1 do FB[i]:=FBuffer[i];
    FBuffer.Position:=0;
    FBuffer.Read(FB, samples);
    if not FLAC__seekable_stream_encoder_process_interleaved(_encoder, @FB[0], samples div FInput.Channels) then
      raise EAcsException.Create('Failed to encode data.');
    Result:=True;
  finally
    FreeMem(FB);
  end;
end;

procedure TFLACOut.SetEnableLooseMidSideStereo();
begin
  if Val then FEnableMidSideStereo:=True;
  FEnableLooseMidSideStereo:=Val;
end;

procedure TFLACOut.SetBestModelSearch();
begin
  if Val then
  begin
    FEnableMidSideStereo:=True;
    FEnableLooseMidSideStereo:=False;
  end;
  FBestModelSearch:=Val;
end;

{ TFLACIn }

constructor TFLACIn.Create();
begin
  inherited Create(AOwner);
  if not (csDesigning	in ComponentState) then
  if not LibFLACLoaded then
  raise EAcsException.Create(LibFLACPath + ' library could not be loaded.');
end;

destructor TFLACIn.Destroy();
begin
  CloseFile();
  inherited Destroy;
end;

procedure TFLACIn.OpenFile();
begin
  if not FOpened then
  begin
    if (FFileName = '') then
      raise EAcsException.Create('File name is not assigned');
    if not Assigned(FStream) then FStream:=TFileStream.Create(FFileName, fmOpenRead, fmShareDenyNone);
    FValid:=True;
    _decoder:=FLAC__seekable_stream_decoder_new;
    if _decoder = nil then
      raise EAcsException.Create('Failed to initialize FLAC decoder.');
    //FLAC__seekable_stream_decoder_set_metadata_ignore_all(_decoder);
    FLAC__seekable_stream_decoder_set_read_callback(_decoder, DecReadCBFunc);
    FLAC__seekable_stream_decoder_set_seek_callback(_decoder, DecSeekCBFunc);
    FLAC__seekable_stream_decoder_set_tell_callback(_decoder, DecTellCBFunc);
    FLAC__seekable_stream_decoder_set_length_callback(_decoder, DecLengthCBFunc);
    FLAC__seekable_stream_decoder_set_eof_callback(_decoder, DecEOFCBFunc);
    FLAC__seekable_stream_decoder_set_write_callback(_decoder, DecWriteCBFunc);
    FLAC__seekable_stream_decoder_set_metadata_callback(_decoder, DecMetadataCBProc);
    FLAC__seekable_stream_decoder_set_error_callback(_decoder, DecErrorCBProc);
    FLAC__seekable_stream_decoder_set_client_data(_decoder, Self);
    if FLAC__seekable_stream_decoder_init(_decoder) <> FLAC__SEEKABLE_STREAM_DECODER_OK then
      raise EAcsException.Create('Failed to initialize FLAC decoder.');
    if not FLAC__seekable_stream_decoder_process_until_end_of_metadata(_decoder) then
      FValid:=False;
    EndOfStream:=False;
    FOpened:=True;
  end;
end;

procedure TFlacIn.CloseFile();
begin
  if FOpened then
  begin
    if _decoder <> nil then
    begin
      FLAC__seekable_stream_decoder_flush(_decoder);
      FLAC__seekable_stream_decoder_finish(_decoder);
      FLAC__seekable_stream_decoder_delete(_decoder);
      _decoder:=nil;
    end;
    if Buff <> nil then FreeMem(Buff);
    Buff:=nil;
    if not FStreamAssigned then FStream.Free
    else FStream.Seek(0, soFromBeginning);
    FOpened:=False;
  end;
end;

function TFLACIn.GetData(Buffer: Pointer; BufferSize: Integer): Integer;
var
  dec_state, offs: Integer;
begin
  if not Active then
    raise EAcsException.Create('The Stream is not opened');
  if BufStart >= BufEnd then
  begin
    if FOffset <> 0 then
    begin
      offs:=Round((FOffset / 100) * Self.FTotalSamples);
      FPosition:=FPosition + offs * (FBPS div 8) * FChan;
      if FPosition < 0 then FPosition:=0
      else if FPosition > FSize then FPosition:=FSize;
      Seek((FPosition div (FBPS div 8)) div FChan);
      FOffset:=0;
    end;
    BufStart:=0;
    BufEnd:=0;
    if FPosition+MinFrameSize > FSize then EndOfStream:=True;
    if EndOfStream then
    begin
      if FLoop then
      begin
        Done();
        Init();
      end
      else
      begin
        Result:=0;
        Exit;
      end;
    end;
    if Buff <> nil then FreeMem(Buff);
    Buff:=nil;
    if not FLAC__seekable_stream_decoder_process_single(_decoder) then
    begin
      dec_state:=FLAC__seekable_stream_decoder_get_state(_decoder);
      if dec_state = FLAC__SEEKABLE_STREAM_DECODER_END_OF_STREAM then
      begin
        EndOfStream:=True;
        Result:=0;
        Exit;
      end
      else
        raise EAcsException.Create('Error reading FLAC file');
    end
    else
      BufEnd:=Self.BytesPerBlock;
  end;
  if BufferSize < (BufEnd - BufStart) then
    Result:=BufferSize
  else
    Result:=BufEnd - BufStart;
  Move(Buff[BufStart], Buffer^, Result);
  Inc(BufStart, Result);
  Inc(FPosition, Result);
end;

function TFLACIn.Seek(SampleNum: Integer): Boolean;
begin
  Result:=FLAC__seekable_stream_decoder_seek_absolute(_decoder, Samplenum);
end;

initialization
  if LoadFlacLibrary() then
  begin
    FileFormats.Add('flac', 'Free Lossless Audio Codec', TFLACIn);
    FileFormats.Add('flac', 'Free Lossless Audio Codec', TFLACOut);
  end;

finalization
  UnloadFlacLibrary();


end.
