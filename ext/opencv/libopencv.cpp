#include <opencv4/opencv2/videoio.hpp>
#include <opencv4/opencv2/highgui.hpp>
#include <opencv4/opencv2/core.hpp>
#include <opencv4/opencv2/imgcodecs.hpp>
#include <opencv4/opencv2/imgproc.hpp>


#include <ruby.h>
#include <stdlib.h>
#include <cstdio>
#include <string>
#include <vector>

cv::VideoCapture camera;
cv::VideoWriter video_writer;
cv::Mat frame; 
bool debug_mode = false;
bool recording = false;
std::string recording_path;
double recording_fps = 30.0;
int camera_width = 0;
int camera_height = 0;

static VALUE open_camera_source(VALUE self, VALUE source, VALUE width, VALUE height) {
    int w = NUM2INT(width);
    int h = NUM2INT(height);
    if (w <= 0 || h <= 0) {
        rb_raise(rb_eArgError, "幅と高さは0より大きい値を指定してください。");
        return Qfalse;
    }

    camera.release();
    camera.open(NUM2INT(source));
    debug_mode = false;

    if (!camera.isOpened()) {
        rb_raise(rb_eRuntimeError, "カメラの起動に失敗しました。");
        return Qfalse;
    }

    camera.set(cv::CAP_PROP_FRAME_WIDTH, w);
    camera.set(cv::CAP_PROP_FRAME_HEIGHT, h);

    camera_width = static_cast<int>(camera.get(cv::CAP_PROP_FRAME_WIDTH));
    camera_height = static_cast<int>(camera.get(cv::CAP_PROP_FRAME_HEIGHT));
    if (camera_width <= 0 || camera_height <= 0) {
        camera_width = w;
        camera_height = h;
    }

    return Qtrue;
}

static VALUE open_mp4_source(VALUE self, VALUE path) {
    if (NIL_P(path) || TYPE(path) != T_STRING || StringValueCStr(path)[0] == '\0') {
        rb_raise(rb_eArgError, "MP4のパスを文字列で指定してください。");
        return Qfalse;
    }

    camera.release();
    camera.open(StringValueCStr(path));
    debug_mode = true;

    if (!camera.isOpened()) {
        rb_raise(rb_eRuntimeError, "MP4動画の起動に失敗しました。");
        return Qfalse;
    }

    camera_width = static_cast<int>(camera.get(cv::CAP_PROP_FRAME_WIDTH));
    camera_height = static_cast<int>(camera.get(cv::CAP_PROP_FRAME_HEIGHT));

    return Qtrue;
}

static VALUE start_recording(VALUE self, VALUE path, VALUE fps) {
    if (recording) {
        rb_raise(rb_eRuntimeError, "動画をすでに録画中です。");
    }

    if (NIL_P(path) || TYPE(path) != T_STRING || StringValueCStr(path)[0] == '\0') {
        rb_raise(rb_eArgError, "保存先パスを文字列で指定してください。");
        return Qfalse;
    }

    recording_path = StringValueCStr(path);
    recording_fps = NUM2DBL(fps);
    if (recording_fps <= 0) {
        rb_raise(rb_eArgError, "FPSは0より大きい値を指定してください。");
        return Qfalse;
    }

    if (!camera.isOpened()) {
        rb_raise(rb_eRuntimeError, "カメラが開かれていません。");
        return Qfalse;
    }

    if (camera_width <= 0 || camera_height <= 0) {
        camera_width = static_cast<int>(camera.get(cv::CAP_PROP_FRAME_WIDTH));
        camera_height = static_cast<int>(camera.get(cv::CAP_PROP_FRAME_HEIGHT));
        if ((camera_width <= 0 || camera_height <= 0) && !frame.empty()) {
            camera_width = frame.cols;
            camera_height = frame.rows;
        }
    }

    if (camera_width <= 0 || camera_height <= 0) {
        rb_raise(rb_eRuntimeError, "カメラの解像度を取得できませんでした。");
        return Qfalse;
    }

    if (video_writer.isOpened()) {
        video_writer.release();
    }

    int codec = cv::VideoWriter::fourcc('H', '2', '6', '4');
    bool opened = video_writer.open(recording_path, codec, recording_fps, cv::Size(camera_width, camera_height), true);
    if (!opened) {
        rb_raise(rb_eRuntimeError, "動画ファイルを開けませんでした。");
        return Qfalse;
    }

    recording = true;
    return Qtrue;
}

static VALUE stop_recording(VALUE self) {
    if (recording) {
        video_writer.release();
        recording = false;
    }
    return Qtrue;
}

static VALUE mat2str(cv::Mat mat) {
    if (mat.empty()) {
        return Qnil; // 空のMatオブジェクトはnilを返す
    }
    std::vector<uchar> buf;
    cv::imencode(".jpg", mat, buf);
    return rb_str_new((const char *)buf.data(), buf.size());
}

static cv::Mat str2mat(VALUE data) {
    if (NIL_P(data)) {
        return cv::Mat();
    }
    std::string ruby_str = std::string(RSTRING_PTR(data), RSTRING_LEN(data));
    std::vector<uchar> cppstr(ruby_str.begin(), ruby_str.end());
    cv::Mat ret = cv::imdecode(cppstr, cv::IMREAD_COLOR);
    return ret;
}

static VALUE write_frame(VALUE self, VALUE image_data) {
    if (!recording) {
        rb_raise(rb_eRuntimeError, "録画が開始されていません。");
        return Qfalse;
    }

    cv::Mat mat = str2mat(image_data);
    if (mat.empty()) {
        rb_raise(rb_eRuntimeError, "フレームデータのデコードに失敗しました。");
        return Qfalse;
    }

    if (!video_writer.isOpened()) {
        rb_raise(rb_eRuntimeError, "動画ファイルが開かれていません。");
        return Qfalse;
    }

    if (camera_width > 0 && camera_height > 0 && (mat.cols != camera_width || mat.rows != camera_height)) {
        cv::resize(mat, mat, cv::Size(camera_width, camera_height));
    }

    video_writer.write(mat);
    return Qtrue;
}

static VALUE take_picture(VALUE self) { // self 引数を追加
    bool ret = camera.read(frame);
    if (!ret || frame.empty()) {
        rb_raise(rb_eRuntimeError, "画像の取得に失敗しました。");
        return Qfalse;
    }

    return mat2str(frame);
}

static VALUE show_movie(VALUE self) {
    cv::imshow("Camera", frame);
    return Qtrue;
}

static VALUE waitKey(int delay) {
    return cv::waitKey(delay);
}

static VALUE destroy_window(VALUE self) {
    cv::destroyAllWindows();
    return Qtrue;
}

extern "C" {
    static VALUE rb_open_mp4(VALUE self, VALUE path) {
        return open_mp4_source(self, path);
    }

    static VALUE rb_cam_open(VALUE self, VALUE source, VALUE width, VALUE height) {
        return open_camera_source(self, source, width, height);
    }

    static VALUE rb_get(VALUE self) {
        return take_picture(self); // 引数の数を修正
    }

    static VALUE rb_start_recording(VALUE self, VALUE path, VALUE fps) {
        return start_recording(self, path, fps);
    }

    static VALUE rb_stop_recording(VALUE self) {
        return stop_recording(self);
    }

    static VALUE rb_write_frame(VALUE self, VALUE image_data) {
        return write_frame(self, image_data);
    }

    static VALUE rb_show_movie(VALUE self) {
        return show_movie(self);
    }

    static VALUE rb_wait_key(VALUE self, VALUE delay) {
        return waitKey(NUM2INT(delay));
    }

    static VALUE rb_destroy_window(VALUE self) {
        return destroy_window(self);
    }

    static VALUE rb_set_frame_pos(VALUE self, VALUE pos) {
        if (!camera.isOpened()) {
            rb_raise(rb_eRuntimeError, "カメラまたは動画が開かれていません。");
            return Qfalse;
        }
        int frame_idx = NUM2INT(pos);
        bool ret = camera.set(cv::CAP_PROP_POS_FRAMES, frame_idx);
        return ret ? Qtrue : Qfalse;
    }

    static VALUE rb_get_frame_pos(VALUE self) {
        if (!camera.isOpened()) {
            return INT2NUM(-1);
        }
        double pos = camera.get(cv::CAP_PROP_POS_FRAMES);
        return INT2NUM(static_cast<int>(pos));
    }

    static VALUE rb_get_total_frames(VALUE self) {
        if (!camera.isOpened()) {
            return INT2NUM(0);
        }
        double count = camera.get(cv::CAP_PROP_FRAME_COUNT);
        return INT2NUM(static_cast<int>(count));
    }

    extern void Init_libopencv(void) {
        VALUE libopencv = rb_define_module("Libopencv");
        rb_define_singleton_method(libopencv, "cam_open", rb_cam_open, 3);
        rb_define_singleton_method(libopencv, "open_mp4", rb_open_mp4, 1);
        rb_define_singleton_method(libopencv, "start_recording", rb_start_recording, 2);
        rb_define_singleton_method(libopencv, "take_picture", rb_get, 0);
        rb_define_singleton_method(libopencv, "write_frame", rb_write_frame, 1);
        rb_define_singleton_method(libopencv, "stop_recording", rb_stop_recording, 0);
        rb_define_singleton_method(libopencv, "show_movie", rb_show_movie, 0);
        rb_define_singleton_method(libopencv, "wait_key", rb_wait_key, 1);
        rb_define_singleton_method(libopencv, "destroy_window", rb_destroy_window, 0);
        rb_define_singleton_method(libopencv, "set_frame_pos", rb_set_frame_pos, 1);
        rb_define_singleton_method(libopencv, "get_frame_pos", rb_get_frame_pos, 0);
        rb_define_singleton_method(libopencv, "get_total_frames", rb_get_total_frames, 0);
    }
}

