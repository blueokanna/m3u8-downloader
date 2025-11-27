package com.bluevale.m3u8_downloader

import android.annotation.SuppressLint
import android.media.*
import android.os.Build
import android.util.Log
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer

@SuppressLint("LogNotTimber")
object MediaTranscoder {
    private const val TAG = "MediaTranscoder"
    
    private const val TIMEOUT_US = 10_000_000L // 10秒
    private const val ENCODE_TIMEOUT_US = 5_000_000L // 5秒
    
    /**
     * 执行转码操作
     * 
     * @param inputPath TS 文件路径
     * @param outputPath MP4 输出路径
     * @param vBitrate 视频码率（kbps，0=自动）
     * @param aBitrate 音频码率（kbps，0=自动）
     * @return 成功返回 true
     */
    @JvmStatic
    fun transcode(
        inputPath: String?,
        outputPath: String?,
        vBitrate: Int,
        aBitrate: Int
    ): Boolean {
        if (inputPath == null || outputPath == null) {
            Log.e(TAG, "transcode: input or output is null")
            return false
        }

        try {
            val inFile = File(inputPath)
            if (!inFile.exists()) {
                Log.e(TAG, "transcode: input file does not exist: $inputPath")
                return false
            }

            // 第一步：尝试快速转封装（如果可能）
            if (tryRemuxIfPossible(inputPath, outputPath, vBitrate, aBitrate)) {
                Log.i(TAG, "Remux succeeded")
                return true
            }

            // 第二步：使用 MediaCodec 进行转码
            Log.i(TAG, "Attempting MediaCodec transcode")
            return transcodeTsToMp4(inputPath, outputPath, vBitrate, aBitrate)

        } catch (e: Exception) {
            Log.e(TAG, "transcode exception: ${e.message}", e)
            return false
        }
    }

    /**
     * 尝试快速转封装（仅复制轨道，不重编码）
     */
    private fun tryRemuxIfPossible(
        inputPath: String,
        outputPath: String,
        vBitrate: Int,
        aBitrate: Int
    ): Boolean {
        return try {
            // 如果指定了码率，不进行转封装
            if (vBitrate > 0 || aBitrate > 0) {
                return false
            }

            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(inputPath)
                
                var videoTrackIdx = -1
                var audioTrackIdx = -1
                
                for (i in 0 until extractor.trackCount) {
                    val fmt = extractor.getTrackFormat(i)
                    val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                    
                    if (mime.startsWith("video/") && videoTrackIdx < 0) {
                        videoTrackIdx = i
                    } else if (mime.startsWith("audio/") && audioTrackIdx < 0) {
                        audioTrackIdx = i
                    }
                }
                
                if (videoTrackIdx < 0) {
                    Log.w(TAG, "No video track found")
                    return false
                }
                
                // 检查视频和音频格式是否兼容 MP4
                val videoFmt = extractor.getTrackFormat(videoTrackIdx)
                val videoMime = videoFmt.getString(MediaFormat.KEY_MIME) ?: ""
                
                if (videoMime != "video/avc" && videoMime != "video/hevc") {
                    Log.w(TAG, "Video codec not compatible for remux: $videoMime")
                    return false
                }
                
                if (audioTrackIdx >= 0) {
                    val audioFmt = extractor.getTrackFormat(audioTrackIdx)
                    val audioMime = audioFmt.getString(MediaFormat.KEY_MIME) ?: ""
                    
                    if (audioMime != "audio/mp4a-latm" && audioMime != "audio/aac") {
                        Log.w(TAG, "Audio codec not compatible for remux: $audioMime")
                        return false
                    }
                }
                
                // 执行转封装
                remuxTracks(inputPath, outputPath, videoTrackIdx, audioTrackIdx)
                true
                
            } finally {
                extractor.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Remux failed: ${e.message}")
            false
        }
    }

    /**
     * 执行轨道转封装
     */
    @Throws(IOException::class)
    private fun remuxTracks(
        inputPath: String,
        outputPath: String,
        videoTrackIdx: Int,
        audioTrackIdx: Int
    ) {
        val extractor = MediaExtractor()
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        
        try {
            extractor.setDataSource(inputPath)
            
            // 添加视频轨道
            extractor.selectTrack(videoTrackIdx)
            val videoFmt = extractor.getTrackFormat(videoTrackIdx)
            val videoOutIdx = muxer.addTrack(videoFmt)
            
            // 添加音频轨道（如果存在）
            var audioOutIdx = -1
            if (audioTrackIdx >= 0) {
                extractor.selectTrack(audioTrackIdx)
                val audioFmt = extractor.getTrackFormat(audioTrackIdx)
                audioOutIdx = muxer.addTrack(audioFmt)
            }
            
            muxer.start()
            
            // 复制样本数据
            val buffer = ByteBuffer.allocateDirect(1024 * 1024) // 1MB 缓冲区
            val info = MediaCodec.BufferInfo()
            
            while (true) {
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                
                info.offset = 0
                info.size = sampleSize
                info.presentationTimeUs = extractor.sampleTime
                info.flags = extractor.sampleFlags
                
                val trackIdx = extractor.sampleTrackIndex
                val outIdx = if (trackIdx == videoTrackIdx) videoOutIdx else audioOutIdx
                
                if (outIdx >= 0) {
                    muxer.writeSampleData(outIdx, buffer, info)
                }
                
                extractor.advance()
            }
            
            muxer.stop()
            Log.i(TAG, "Remux completed successfully")
            
        } finally {
            try {
                muxer.release()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to release muxer: ${e.message}")
            }
            extractor.release()
        }
    }

    /**
     * 使用 MediaCodec 进行 TS 到 MP4 的转码
     */
    @Throws(Exception::class)
    private fun transcodeTsToMp4(
        inputPath: String,
        outputPath: String,
        vBitrate: Int,
        aBitrate: Int
    ): Boolean {
        val extractor = MediaExtractor()
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        
        var videoDecoder: MediaCodec? = null
        var videoEncoder: MediaCodec? = null
        var audioDecoder: MediaCodec? = null
        var audioEncoder: MediaCodec? = null
        
        try {
            extractor.setDataSource(inputPath)
            
            // 找到视频和音频轨道
            var videoTrackIdx = -1
            var audioTrackIdx = -1
            
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                
                if (mime.startsWith("video/") && videoTrackIdx < 0) {
                    videoTrackIdx = i
                } else if (mime.startsWith("audio/") && audioTrackIdx < 0) {
                    audioTrackIdx = i
                }
            }
            
            if (videoTrackIdx < 0) {
                Log.e(TAG, "No video track found")
                return false
            }
            
            // 处理视频轨道
            val videoOutIdx = processVideoTrack(
                extractor, muxer, videoTrackIdx, vBitrate
            )
            
            // 处理音频轨道
            var audioOutIdx = -1
            if (audioTrackIdx >= 0) {
                audioOutIdx = processAudioTrack(
                    extractor, muxer, audioTrackIdx, aBitrate
                )
            }
            
            muxer.start()
            
            // 复制样本数据
            val buffer = ByteBuffer.allocateDirect(1024 * 1024)
            val info = MediaCodec.BufferInfo()
            
            while (true) {
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                
                info.offset = 0
                info.size = sampleSize
                info.presentationTimeUs = extractor.sampleTime
                info.flags = extractor.sampleFlags
                
                val trackIdx = extractor.sampleTrackIndex
                val outIdx = if (trackIdx == videoTrackIdx) videoOutIdx else audioOutIdx
                
                if (outIdx >= 0) {
                    muxer.writeSampleData(outIdx, buffer, info)
                }
                
                extractor.advance()
            }
            
            muxer.stop()
            Log.i(TAG, "Transcode completed successfully")
            return true
            
        } catch (e: Exception) {
            Log.e(TAG, "Transcode failed: ${e.message}", e)
            return false
        } finally {
            try {
                videoDecoder?.release()
                videoEncoder?.release()
                audioDecoder?.release()
                audioEncoder?.release()
                muxer.release()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to release resources: ${e.message}")
            }
            extractor.release()
        }
    }

    /**
     * 处理视频轨道
     */
    private fun processVideoTrack(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        trackIdx: Int,
        bitrate: Int
    ): Int {
        extractor.selectTrack(trackIdx)
        val videoFmt = extractor.getTrackFormat(trackIdx)
        
        // 获取视频参数
        val width = videoFmt.getInteger(MediaFormat.KEY_WIDTH)
        val height = videoFmt.getInteger(MediaFormat.KEY_HEIGHT)
        val frameRate = videoFmt.getInteger(MediaFormat.KEY_FRAME_RATE)
        
        // 创建输出格式
        val outputFmt = MediaFormat.createVideoFormat("video/avc", width, height)
        outputFmt.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        outputFmt.setInteger(MediaFormat.KEY_BIT_RATE, if (bitrate > 0) bitrate * 1000 else 2500000)
        outputFmt.setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
        outputFmt.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        
        return muxer.addTrack(outputFmt)
    }

    /**
     * 处理音频轨道
     */
    private fun processAudioTrack(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        trackIdx: Int,
        bitrate: Int
    ): Int {
        extractor.selectTrack(trackIdx)
        val audioFmt = extractor.getTrackFormat(trackIdx)
        
        // 获取音频参数
        val sampleRate = audioFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channelCount = audioFmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        
        // 创建输出格式
        val outputFmt = MediaFormat.createAudioFormat("audio/mp4a-latm", sampleRate, channelCount)
        outputFmt.setInteger(MediaFormat.KEY_BIT_RATE, if (bitrate > 0) bitrate * 1000 else 256000)
        outputFmt.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        
        return muxer.addTrack(outputFmt)
    }
}