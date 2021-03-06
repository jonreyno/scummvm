/* ScummVM - Graphic Adventure Engine
 *
 * ScummVM is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

// Disable symbol overrides so that we can use system headers.
#define FORBIDDEN_SYMBOL_ALLOW_ALL

#include "backends/platform/ios7/ios7_video.h"

#include "graphics/colormasks.h"
#include "common/system.h"
#include "backends/platform/ios7/ios7_app_delegate.h"

static int g_needsScreenUpdate = 0;

#if 0
static long g_lastTick = 0;
static int g_frames = 0;
#endif

#define printOpenGLError() printOglError(__FILE__, __LINE__)

int printOglError(const char *file, int line) {
	int retCode = 0;

	// returns 1 if an OpenGL error occurred, 0 otherwise.
	GLenum glErr = glGetError();
	while (glErr != GL_NO_ERROR) {
		fprintf(stderr, "glError: %u (%s: %d)\n", glErr, file, line);
		retCode = 1;
		glErr = glGetError();
	}
	return retCode;
}

bool iOS7_isBigDevice() {
	return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
}

static inline void execute_on_main_thread(void (^block)(void)) {
	if ([NSThread currentThread] == [NSThread mainThread]) {
		block();
	}
	else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

void iOS7_updateScreen() {
	//printf("Mouse: (%i, %i)\n", mouseX, mouseY);
	if (!g_needsScreenUpdate) {
		g_needsScreenUpdate = 1;
		execute_on_main_thread(^{
			[[iOS7AppDelegate iPhoneView] updateSurface];
		});
	}
}

bool iOS7_fetchEvent(InternalEvent *event) {
	__block bool fetched;
	execute_on_main_thread(^{
		fetched = [[iOS7AppDelegate iPhoneView] fetchEvent:event];
	});
	return fetched;
}

uint getSizeNextPOT(uint size) {
	if ((size & (size - 1)) || !size) {
		int log = 0;

		while (size >>= 1)
			++log;

		size = (2 << log);
	}

	return size;
}

@implementation iPhoneView

+ (Class)layerClass {
	return [CAEAGLLayer class];
}

- (VideoContext *)getVideoContext {
	return &_videoContext;
}

- (void)createContext {
	CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;

	eaglLayer.opaque = YES;
	eaglLayer.drawableProperties = @{
	                                 kEAGLDrawablePropertyRetainedBacking: @NO,
	                                 kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGB565
	                                };

	_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

	// In case creating the OpenGL ES context failed, we will error out here.
	if (_context == nil) {
		fprintf(stderr, "Could not create OpenGL ES context\n");
		exit(-1);
	}

	if ([EAGLContext setCurrentContext:_context]) {
		// glEnableClientState(GL_TEXTURE_COORD_ARRAY); printOpenGLError();
		// glEnableClientState(GL_VERTEX_ARRAY); printOpenGLError();
		[self setupOpenGL];
	}
}

- (void)setupOpenGL {
	[self setupFramebuffer];
	[self createOverlaySurface];
	[self compileShaders];
	[self setupVBOs];
	[self setupTextures];

	[self finishGLSetup];
}

- (void)finishGLSetup {
	glViewport(0, 0, _renderBufferWidth, _renderBufferHeight); printOpenGLError();
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f); printOpenGLError();

	glUniform2f(_screenSizeSlot, _renderBufferWidth, _renderBufferHeight);

	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

- (void)freeOpenGL {
	[self deleteTextures];
	[self deleteVBOs];
	[self deleteShaders];
	[self deleteFramebuffer];
}

- (void)rebuildFrameBuffer {
	[self deleteFramebuffer];
	[self setupFramebuffer];
	[self finishGLSetup];
}

- (void)setupFramebuffer {
	glGenRenderbuffers(1, &_viewRenderbuffer);
	printOpenGLError();
	glBindRenderbuffer(GL_RENDERBUFFER, _viewRenderbuffer);
	printOpenGLError();
	[_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(id <EAGLDrawable>) self.layer];

	glGenFramebuffers(1, &_viewFramebuffer);
	printOpenGLError();
	glBindFramebuffer(GL_FRAMEBUFFER, _viewFramebuffer);
	printOpenGLError();
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _viewRenderbuffer);
	printOpenGLError();

	// Retrieve the render buffer size. This *should* match the frame size,
	// i.e. g_fullWidth and g_fullHeight.
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_renderBufferWidth);
	printOpenGLError();
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_renderBufferHeight);
	printOpenGLError();

	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		NSLog(@"Failed to make complete framebuffer object %x.", glCheckFramebufferStatus(GL_FRAMEBUFFER));
		return;
	}
}

- (void)createOverlaySurface {
	uint overlayWidth = (uint) MAX(_renderBufferWidth, _renderBufferHeight);
	uint overlayHeight = (uint) MIN(_renderBufferWidth, _renderBufferHeight);

	if (iOS7_isBigDevice()) {
		// On really big displays, like the iPad Pro, we scale the interface down
		// so that the controls are not too small..
		while (overlayHeight > 1024) {
			overlayWidth /= 2;
			overlayHeight /= 2;
		}
	}
	else {
		// On small devices, we force the user interface to use the small theme
		while (overlayHeight > 480) {
			overlayWidth /= 2;
			overlayHeight /= 2;
		}
	}

	_videoContext.overlayWidth = overlayWidth;
	_videoContext.overlayHeight = overlayHeight;

	uint overlayTextureWidthPOT  = getSizeNextPOT(overlayWidth);
	uint overlayTextureHeightPOT = getSizeNextPOT(overlayHeight);

	// Since the overlay size won't change the whole run, we can
	// precalculate the texture coordinates for the overlay texture here
	// and just use it later on.
	GLfloat u = _videoContext.overlayWidth / (GLfloat) overlayTextureWidthPOT;
	GLfloat v = _videoContext.overlayHeight / (GLfloat) overlayTextureHeightPOT;
	_overlayCoords[0].x = 0; _overlayCoords[0].y = 0; _overlayCoords[0].u = 0; _overlayCoords[0].v = 0;
	_overlayCoords[1].x = 0; _overlayCoords[1].y = 0; _overlayCoords[1].u = u; _overlayCoords[1].v = 0;
	_overlayCoords[2].x = 0; _overlayCoords[2].y = 0; _overlayCoords[2].u = 0; _overlayCoords[2].v = v;
	_overlayCoords[3].x = 0; _overlayCoords[3].y = 0; _overlayCoords[3].u = u; _overlayCoords[3].v = v;

	_videoContext.overlayTexture.create((uint16) overlayTextureWidthPOT, (uint16) overlayTextureHeightPOT, Graphics::createPixelFormat<5551>());
}

- (void)deleteFramebuffer {
	glDeleteRenderbuffers(1, &_viewRenderbuffer);
	glDeleteFramebuffers(1, &_viewFramebuffer);
}

- (void)setupVBOs {
	glGenBuffers(1, &_vertexBuffer);
	glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
}

- (void)deleteVBOs {
	glDeleteBuffers(1, &_vertexBuffer);
}

- (GLuint)compileShader:(const char*)shaderPrg withType:(GLenum)shaderType {
	GLuint shaderHandle = glCreateShader(shaderType);

	int shaderPrgLength = strlen(shaderPrg);
	glShaderSource(shaderHandle, 1, &shaderPrg, &shaderPrgLength);

	glCompileShader(shaderHandle);

	GLint compileSuccess;
	glGetShaderiv(shaderHandle, GL_COMPILE_STATUS, &compileSuccess);
	if (compileSuccess == GL_FALSE) {
		GLchar messages[256];
		glGetShaderInfoLog(shaderHandle, sizeof(messages), 0, &messages[0]);
		NSString *messageString = [NSString stringWithUTF8String:messages];
		NSLog(@"%@", messageString);
		exit(1);
	}

	return shaderHandle;
}

- (void)compileShaders {
	const char *vertexPrg =
			"uniform vec2 ScreenSize;"
			"uniform float Shake;"
			""
			"attribute vec2 Position;"
			"attribute vec2 TexCoord;"
			""
			"varying vec4 DestColor;"
			"varying vec2 o_TexCoord;"
			""
			"void main(void) {"
			"	DestColor = vec4(Position.x, Position.y, 0, 1);"
			"	o_TexCoord = TexCoord;"
			"	gl_Position = vec4((Position.x / ScreenSize.x) * 2.0 - 1.0, (1.0 - (Position.y + Shake) / ScreenSize.y) * 2.0 - 1.0, 0, 1);"
			"}";

	const char *fragmentPrg =
			"uniform sampler2D Texture;"
			""
			"varying lowp vec4 DestColor;"
			"varying lowp vec2 o_TexCoord;"
			""
			"void main(void) {"
			"	gl_FragColor = texture2D(Texture, o_TexCoord);"
			"}";

	_vertexShader = [self compileShader:vertexPrg withType:GL_VERTEX_SHADER];
	_fragmentShader = [self compileShader:fragmentPrg withType:GL_FRAGMENT_SHADER];

	GLuint programHandle = glCreateProgram();
	glAttachShader(programHandle, _vertexShader);
	glAttachShader(programHandle, _fragmentShader);
	glLinkProgram(programHandle);

	GLint linkSuccess;
	glGetProgramiv(programHandle, GL_LINK_STATUS, &linkSuccess);
	if (linkSuccess == GL_FALSE) {
		printOpenGLError();
		exit(1);
	}

	glUseProgram(programHandle);

	_screenSizeSlot = (GLuint) glGetUniformLocation(programHandle, "ScreenSize");
	_textureSlot = (GLuint) glGetUniformLocation(programHandle, "Texture");
	_shakeSlot = (GLuint) glGetUniformLocation(programHandle, "Shake");

	_positionSlot = (GLuint) glGetAttribLocation(programHandle, "Position");
	_textureCoordSlot = (GLuint) glGetAttribLocation(programHandle, "TexCoord");

	glEnableVertexAttribArray(_positionSlot);
	glEnableVertexAttribArray(_textureCoordSlot);

	glUniform1i(_textureSlot, 0); printOpenGLError();
}

- (void)deleteShaders {
	glDeleteShader(_vertexShader);
	glDeleteShader(_fragmentShader);
}

- (void)setupTextures {
	glGenTextures(1, &_screenTexture); printOpenGLError();
	glGenTextures(1, &_overlayTexture); printOpenGLError();
	glGenTextures(1, &_mouseCursorTexture); printOpenGLError();

	[self setGraphicsMode];
}

- (void)deleteTextures {
	if (_screenTexture) {
		glDeleteTextures(1, &_screenTexture); printOpenGLError();
		_screenTexture = 0;
	}
	if (_overlayTexture) {
		glDeleteTextures(1, &_overlayTexture); printOpenGLError();
		_overlayTexture = 0;
	}
	if (_mouseCursorTexture) {
		glDeleteTextures(1, &_mouseCursorTexture); printOpenGLError();
		_mouseCursorTexture = 0;
	}
}

- (void)setupGestureRecognizers {
    UIPanGestureRecognizer *panOneFinger = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    panOneFinger.maximumNumberOfTouches = 1;
    panOneFinger.delaysTouchesBegan = NO;
    panOneFinger.delaysTouchesEnded = NO;
    panOneFinger.cancelsTouchesInView = YES;
    
    UISwipeGestureRecognizer *swipeRightOneFinger = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight:)];
    swipeRightOneFinger.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRightOneFinger.numberOfTouchesRequired = 1;
    swipeRightOneFinger.delaysTouchesBegan = NO;
    swipeRightOneFinger.delaysTouchesEnded = NO;
    swipeRightOneFinger.cancelsTouchesInView = NO;
    
    UISwipeGestureRecognizer *swipeRightTwoFinger = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight:)];
    swipeRightTwoFinger.direction = UISwipeGestureRecognizerDirectionRight;
    swipeRightTwoFinger.numberOfTouchesRequired = 2;
    swipeRightTwoFinger.delaysTouchesBegan = NO;
    swipeRightTwoFinger.delaysTouchesEnded = NO;
    swipeRightTwoFinger.cancelsTouchesInView = NO;
    
    UISwipeGestureRecognizer *swipeLeftOneFinger = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft:)];
    swipeLeftOneFinger.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeftOneFinger.numberOfTouchesRequired = 1;
    swipeLeftOneFinger.delaysTouchesBegan = NO;
    swipeLeftOneFinger.delaysTouchesEnded = NO;
    swipeLeftOneFinger.cancelsTouchesInView = NO;
    
    UISwipeGestureRecognizer *swipeLeftTwoFinger = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft:)];
    swipeLeftTwoFinger.direction = UISwipeGestureRecognizerDirectionLeft;
    swipeLeftTwoFinger.numberOfTouchesRequired = 2;
    swipeLeftTwoFinger.delaysTouchesBegan = NO;
    swipeLeftTwoFinger.delaysTouchesEnded = NO;
    swipeLeftTwoFinger.cancelsTouchesInView = NO;
    
    UISwipeGestureRecognizer *swipeUpOneFinger = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp:)];
    swipeUpOneFinger.direction = UISwipeGestureRecognizerDirectionUp;
    swipeUpOneFinger.numberOfTouchesRequired = 1;
    swipeUpOneFinger.delaysTouchesBegan = NO;
    swipeUpOneFinger.delaysTouchesEnded = NO;
    swipeUpOneFinger.cancelsTouchesInView = NO;
    
    UISwipeGestureRecognizer *swipeUpTwoFinger = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp:)];
    swipeUpTwoFinger.direction = UISwipeGestureRecognizerDirectionUp;
    swipeUpTwoFinger.numberOfTouchesRequired = 2;
    swipeUpTwoFinger.delaysTouchesBegan = NO;
    swipeUpTwoFinger.delaysTouchesEnded = NO;
    swipeUpTwoFinger.cancelsTouchesInView = NO;
    
    UISwipeGestureRecognizer *swipeDownOneFinger = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown:)];
    swipeDownOneFinger.direction = UISwipeGestureRecognizerDirectionDown;
    swipeDownOneFinger.numberOfTouchesRequired = 1;
    swipeDownOneFinger.delaysTouchesBegan = NO;
    swipeDownOneFinger.delaysTouchesEnded = NO;
    swipeDownOneFinger.cancelsTouchesInView = NO;
    
    UISwipeGestureRecognizer *swipeDownTwoFinger = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown:)];
    swipeDownTwoFinger.direction = UISwipeGestureRecognizerDirectionDown;
    swipeDownTwoFinger.numberOfTouchesRequired = 2;
    swipeDownTwoFinger.delaysTouchesBegan = NO;
    swipeDownTwoFinger.delaysTouchesEnded = NO;
    swipeDownTwoFinger.cancelsTouchesInView = NO;
    
    UITapGestureRecognizer *doubleTapOneFinger = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    doubleTapOneFinger.numberOfTapsRequired = 2;
    doubleTapOneFinger.numberOfTouchesRequired = 1;
    doubleTapOneFinger.delaysTouchesBegan = NO;
    doubleTapOneFinger.delaysTouchesEnded = NO;
    
    UITapGestureRecognizer *doubleTapTwoFinger = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    doubleTapTwoFinger.numberOfTapsRequired = 2;
    doubleTapTwoFinger.numberOfTouchesRequired = 2;
    doubleTapTwoFinger.delaysTouchesBegan = NO;
    doubleTapTwoFinger.delaysTouchesEnded = NO;
    
    UITapGestureRecognizer *singleTapOneFinger = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTap:)];
    singleTapOneFinger.numberOfTapsRequired = 1;
    singleTapOneFinger.numberOfTouchesRequired = 1;
    singleTapOneFinger.delaysTouchesBegan = NO;
    singleTapOneFinger.delaysTouchesEnded = NO;
    singleTapOneFinger.cancelsTouchesInView = NO;
    
    UITapGestureRecognizer *singleTapTwoFinger = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(singleTap:)];
    singleTapTwoFinger.numberOfTapsRequired = 1;
    singleTapTwoFinger.numberOfTouchesRequired = 2;
    singleTapTwoFinger.delaysTouchesBegan = NO;
    singleTapTwoFinger.delaysTouchesEnded = NO;
    singleTapTwoFinger.cancelsTouchesInView = NO;
    
    UILongPressGestureRecognizer *singlePressOneFinger = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(singlePress:)];
    singlePressOneFinger.numberOfTapsRequired = 0;
    singlePressOneFinger.numberOfTouchesRequired = 1;
    singlePressOneFinger.allowableMovement = 10;
    singlePressOneFinger.minimumPressDuration = 0.3;
    singlePressOneFinger.delaysTouchesBegan = NO;
    singlePressOneFinger.delaysTouchesEnded = NO;
    singlePressOneFinger.cancelsTouchesInView = YES;
    
    UILongPressGestureRecognizer *doublePressOneFinger = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(doublePress:)];
    doublePressOneFinger.numberOfTapsRequired = 1;
    doublePressOneFinger.numberOfTouchesRequired = 1;
    doublePressOneFinger.allowableMovement = 5;
    doublePressOneFinger.minimumPressDuration = 0.3;
    doublePressOneFinger.delaysTouchesBegan = NO;
    doublePressOneFinger.delaysTouchesEnded = NO;
    doublePressOneFinger.cancelsTouchesInView = YES;
    
    [self addGestureRecognizer:panOneFinger];
    [self addGestureRecognizer:swipeRightOneFinger];
    [self addGestureRecognizer:swipeRightTwoFinger];
    [self addGestureRecognizer:swipeLeftOneFinger];
    [self addGestureRecognizer:swipeLeftTwoFinger];
    [self addGestureRecognizer:swipeUpOneFinger];
    [self addGestureRecognizer:swipeUpTwoFinger];
    [self addGestureRecognizer:swipeDownOneFinger];
    [self addGestureRecognizer:swipeDownTwoFinger];
    [self addGestureRecognizer:doubleTapOneFinger];
    [self addGestureRecognizer:doubleTapTwoFinger];
    [self addGestureRecognizer:singleTapOneFinger];
    [self addGestureRecognizer:singleTapTwoFinger];
    [self addGestureRecognizer:singlePressOneFinger];
    [self addGestureRecognizer:doublePressOneFinger];
    
    [panOneFinger release];
    [swipeRightOneFinger release];
    [swipeRightTwoFinger release];
    [swipeLeftOneFinger release];
    [swipeLeftTwoFinger release];
    [swipeUpOneFinger release];
    [swipeUpTwoFinger release];
    [swipeDownOneFinger release];
    [swipeDownTwoFinger release];
    [doubleTapOneFinger release];
    [doubleTapTwoFinger release];
    [singleTapOneFinger release];
    [singleTapTwoFinger release];
    [singlePressOneFinger release];
    [doublePressOneFinger release];
    
    //[panOneFinger requireGestureRecognizerToFail:swipeUpOneFinger];
    //[panOneFinger requireGestureRecognizerToFail:swipeDownOneFinger];
    //[panOneFinger requireGestureRecognizerToFail:swipeLeftOneFinger];
    //[panOneFinger requireGestureRecognizerToFail:swipeRightOneFinger];
    //[singleTapOneFinger requireGestureRecognizerToFail : doubleTapOneFinger];
}

- (id)initWithFrame:(struct CGRect)frame {
	self = [super initWithFrame: frame];

#if defined(USE_SCALERS) || defined(USE_HQ_SCALERS)
	InitScalers(565);
#endif

	[self setupGestureRecognizers];

	[self setContentScaleFactor:[[UIScreen mainScreen] scale]];

#ifdef ENABLE_IOS7_SCALERS
	_scalerMemorySrc = NULL;
	_scalerMemoryDst = NULL;
	_scalerMemorySrcSize = 0;
	_scalerMemoryDstSize = 0;
	_scaler = NULL;
	_scalerScale = 1;
#endif

	_keyboardView = nil;
	_screenTexture = 0;
	_overlayTexture = 0;
	_mouseCursorTexture = 0;

	_scaledShakeOffsetY = 0;

	_firstTouch = NULL;
	_secondTouch = NULL;

	_eventLock = [[NSLock alloc] init];

	memset(_gameScreenCoords, 0, sizeof(GLVertex) * 4);
	memset(_overlayCoords, 0, sizeof(GLVertex) * 4);
	memset(_mouseCoords, 0, sizeof(GLVertex) * 4);

	// Initialize the OpenGL ES context
	[self createContext];

	return self;
}

- (void)dealloc {
	[_keyboardView release];

	_videoContext.screenTexture.free();
	_videoContext.overlayTexture.free();
	_videoContext.mouseTexture.free();

#ifdef ENABLE_IOS7_SCALERS
	free(_scalerMemorySrc);
	free(_scalerMemoryDst);
#endif

	[_eventLock release];
	[super dealloc];
}

- (void)setFilterModeForTexture:(GLuint)tex {
	if (!tex)
		return;

	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, tex); printOpenGLError();

	GLint filter = _videoContext.filtering ? GL_LINEAR : GL_NEAREST;

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter); printOpenGLError();
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter); printOpenGLError();
	// We use GL_CLAMP_TO_EDGE here to avoid artifacts when linear filtering
	// is used. If we would not use this for example the cursor in Loom would
	// have a line/border artifact on the right side of the covered rect.
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE); printOpenGLError();
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE); printOpenGLError();
}

#ifdef ENABLE_IOS7_SCALERS
- (void)setScaler {
	ScalerProc *scaler = NULL;
	int scalerScale = 1;

	switch (_videoContext.graphicsMode) {
	case kGraphicsModeNone:
		break;
#ifdef USE_SCALERS
	case kGraphicsMode2xSaI:
		scaler = _2xSaI;
		scalerScale = 2;
		break;

	case kGraphicsModeSuper2xSaI:
		scaler = Super2xSaI;
		scalerScale = 2;
		break;

	case kGraphicsModeSuperEagle:
		scaler = SuperEagle;
		scalerScale = 2;
		break;

	case kGraphicsModeAdvMame2x:
		scaler = AdvMame2x;
		scalerScale = 2;
		break;

	case kGraphicsModeAdvMame3x:
		scaler = AdvMame3x;
		scalerScale = 3;
		break;

#ifdef USE_HQ_SCALERS
	case kGraphicsModeHQ2x:
		scaler = HQ2x;
		scalerScale = 2;
		break;

	case kGraphicsModeHQ3x:
		scaler = HQ3x;
		scalerScale = 3;
		break;
#endif

	case kGraphicsModeTV2x:
		scaler = TV2x;
		scalerScale = 2;
		break;

	case kGraphicsModeDotMatrix:
		scaler = DotMatrix;
		scalerScale = 2;
		break;
#endif

	default:
		break;
	}

	_scaler = scaler;
	_scalerScale = scalerScale;
}
#endif

- (void)setGraphicsMode {
	[self setFilterModeForTexture:_screenTexture];
	[self setFilterModeForTexture:_overlayTexture];
	[self setFilterModeForTexture:_mouseCursorTexture];
#ifdef ENABLE_IOS7_SCALERS
	[self setScaler];
#endif
}

- (void)updateSurface {
	if (!g_needsScreenUpdate) {
		return;
	}
	g_needsScreenUpdate = 0;

	glClear(GL_COLOR_BUFFER_BIT); printOpenGLError();

	[self updateMainSurface];

	if (_videoContext.overlayVisible)
		[self updateOverlaySurface];

	if (_videoContext.mouseIsVisible)
		[self updateMouseSurface];

	[_context presentRenderbuffer:GL_RENDERBUFFER];
	glFinish();
}

- (void)notifyMouseMove {
	const GLint mouseX = (GLint)(_videoContext.mouseX * _mouseScaleX) - _mouseHotspotX;
	const GLint mouseY = (GLint)(_videoContext.mouseY * _mouseScaleY) - _mouseHotspotY;

	_mouseCoords[0].x = _mouseCoords[2].x = mouseX;
	_mouseCoords[0].y = _mouseCoords[1].y = mouseY;
	_mouseCoords[1].x = _mouseCoords[3].x = mouseX + _mouseWidth;
	_mouseCoords[2].y = _mouseCoords[3].y = mouseY + _mouseHeight;
}

- (void)updateMouseCursorScaling {
	CGRect *rect;
	int maxWidth, maxHeight;

	if (!_videoContext.overlayVisible) {
		rect = &_gameScreenRect;
		maxWidth = _videoContext.screenWidth;
		maxHeight = _videoContext.screenHeight;
	} else {
		rect = &_overlayRect;
		maxWidth = _videoContext.overlayWidth;
		maxHeight = _videoContext.overlayHeight;
	}

	if (!maxWidth || !maxHeight) {
		printf("WARNING: updateMouseCursorScaling called when screen was not ready (%d)!\n", _videoContext.overlayVisible);
		return;
	}

	_mouseScaleX = CGRectGetWidth(*rect) / (GLfloat)maxWidth;
	_mouseScaleY = CGRectGetHeight(*rect) / (GLfloat)maxHeight;

	_mouseWidth = (GLint)(_videoContext.mouseWidth * _mouseScaleX);
	_mouseHeight = (GLint)(_videoContext.mouseHeight * _mouseScaleY);

	_mouseHotspotX = (GLint)(_videoContext.mouseHotspotX * _mouseScaleX);
	_mouseHotspotY = (GLint)(_videoContext.mouseHotspotY * _mouseScaleY);

	// We subtract the screen offset to the hotspot here to simplify the
	// screen offset handling in the mouse code. Note the subtraction here
	// makes sure that the offset actually gets added to the mouse position,
	// since the hotspot offset is substracted from the position.
	_mouseHotspotX -= (GLint)CGRectGetMinX(*rect);
	_mouseHotspotY -= (GLint)CGRectGetMinY(*rect);

	// FIXME: For now we also adapt the mouse position here. In reality we
	// would be better off to also adjust the event position when switching
	// from overlay to game screen or vica versa.
	[self notifyMouseMove];
}

- (void)updateMouseCursor {
	[self updateMouseCursorScaling];

	_mouseCoords[1].u = _mouseCoords[3].u = (_videoContext.mouseWidth - 1) / (GLfloat)_videoContext.mouseTexture.w;
	_mouseCoords[2].v = _mouseCoords[3].v = (_videoContext.mouseHeight - 1) / (GLfloat)_videoContext.mouseTexture.h;

	[self setFilterModeForTexture:_mouseCursorTexture];
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _videoContext.mouseTexture.w, _videoContext.mouseTexture.h, 0, GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1, _videoContext.mouseTexture.getPixels()); printOpenGLError();
}

- (void)updateMainSurface {
	glBufferData(GL_ARRAY_BUFFER, sizeof(GLVertex) * 4, _gameScreenCoords, GL_STATIC_DRAW);
	glVertexAttribPointer(_positionSlot, 2, GL_FLOAT, GL_FALSE, sizeof(GLVertex), 0);
	glVertexAttribPointer(_textureCoordSlot, 2, GL_FLOAT, GL_FALSE, sizeof(GLVertex), (GLvoid *) (sizeof(GLfloat) * 2));

	[self setFilterModeForTexture:_screenTexture];

	// Unfortunately we have to update the whole texture every frame, since glTexSubImage2D is actually slower in all cases
	// due to the iPhone internals having to convert the whole texture back from its internal format when used.
	// In the future we could use several tiled textures instead.
#ifdef ENABLE_IOS7_SCALERS
	if (_scaler) {
		size_t neededSrcMemorySize = (size_t) (_videoContext.screenTexture.pitch * (_videoContext.screenTexture.h + 4));
		size_t neededDstMemorySize = (size_t) (_videoContext.screenTexture.pitch * (_videoContext.screenTexture.h + 4) * _scalerScale * _scalerScale);
		if (neededSrcMemorySize != _scalerMemorySrcSize) {
			_scalerMemorySrc = (uint8_t *) realloc(_scalerMemorySrc, neededSrcMemorySize);
			_scalerMemorySrcSize = neededSrcMemorySize;
		}
		if (neededDstMemorySize != _scalerMemoryDstSize) {
			_scalerMemoryDst = (uint8_t *) realloc(_scalerMemoryDst, neededDstMemorySize);
			_scalerMemoryDstSize = neededDstMemorySize;
		}

		// Clear two lines before
		memset(_scalerMemorySrc, 0, (size_t) (_videoContext.screenTexture.pitch * 2));
		// Copy original buffer
		memcpy(_scalerMemorySrc + _videoContext.screenTexture.pitch * 2, _videoContext.screenTexture.getPixels(), _videoContext.screenTexture.pitch * _videoContext.screenTexture.h);
		// Clear two lines after
		memset(_scalerMemorySrc + _videoContext.screenTexture.pitch * (2 + _videoContext.screenTexture.h), 0, (size_t) (_videoContext.screenTexture.pitch * 2));
		// Apply scaler
		_scaler(_scalerMemorySrc + _videoContext.screenTexture.pitch * 2,
		        _videoContext.screenTexture.pitch,
		        _scalerMemoryDst,
		        (uint32) (_videoContext.screenTexture.pitch * _scalerScale),
		        _videoContext.screenTexture.w,
		        _videoContext.screenTexture.h);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, _videoContext.screenTexture.w * _scalerScale, _videoContext.screenTexture.h * _scalerScale, 0, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, _scalerMemoryDst); printOpenGLError();
	}
	else {
#endif
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, _videoContext.screenTexture.w, _videoContext.screenTexture.h, 0, GL_RGB, GL_UNSIGNED_SHORT_5_6_5, _videoContext.screenTexture.getPixels()); printOpenGLError();
#ifdef ENABLE_IOS7_SCALERS
	}
#endif

	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); printOpenGLError();
}

- (void)updateOverlaySurface {
	glBufferData(GL_ARRAY_BUFFER, sizeof(GLVertex) * 4, _overlayCoords, GL_STATIC_DRAW);
	glVertexAttribPointer(_positionSlot, 2, GL_FLOAT, GL_FALSE, sizeof(GLVertex), 0);
	glVertexAttribPointer(_textureCoordSlot, 2, GL_FLOAT, GL_FALSE, sizeof(GLVertex), (GLvoid *) (sizeof(GLfloat) * 2));

	[self setFilterModeForTexture:_overlayTexture];

	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, _videoContext.overlayTexture.w, _videoContext.overlayTexture.h, 0, GL_RGBA, GL_UNSIGNED_SHORT_5_5_5_1, _videoContext.overlayTexture.getPixels()); printOpenGLError();
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); printOpenGLError();
}

- (void)updateMouseSurface {
	glBufferData(GL_ARRAY_BUFFER, sizeof(GLVertex) * 4, _mouseCoords, GL_STATIC_DRAW);
	glVertexAttribPointer(_positionSlot, 2, GL_FLOAT, GL_FALSE, sizeof(GLVertex), 0);
	glVertexAttribPointer(_textureCoordSlot, 2, GL_FLOAT, GL_FALSE, sizeof(GLVertex), (GLvoid *) (sizeof(GLfloat) * 2));

	glBindTexture(GL_TEXTURE_2D, _mouseCursorTexture); printOpenGLError();

	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); printOpenGLError();
}

- (void)createScreenTexture {
	const uint screenTexWidth = getSizeNextPOT(_videoContext.screenWidth);
	const uint screenTexHeight = getSizeNextPOT(_videoContext.screenHeight);

	_gameScreenCoords[1].u = _gameScreenCoords[3].u = _videoContext.screenWidth / (GLfloat)screenTexWidth;
	_gameScreenCoords[2].v = _gameScreenCoords[3].v = _videoContext.screenHeight / (GLfloat)screenTexHeight;

	_videoContext.screenTexture.create((uint16) screenTexWidth, (uint16) screenTexHeight, Graphics::createPixelFormat<565>());
}

- (void)initSurface {
	if (_context) {
		[self rebuildFrameBuffer];
	}

	BOOL isLandscape = (self.bounds.size.width > self.bounds.size.height); // UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation]);

	int screenWidth, screenHeight;
	if (isLandscape) {
		screenWidth = MAX(_renderBufferWidth, _renderBufferHeight);
		screenHeight = MIN(_renderBufferWidth, _renderBufferHeight);
	}
	else {
		screenWidth = MIN(_renderBufferWidth, _renderBufferHeight);
		screenHeight = MAX(_renderBufferWidth, _renderBufferHeight);
	}

	if (_keyboardView == nil) {
		_keyboardView = [[SoftKeyboard alloc] initWithFrame:CGRectZero];
		[_keyboardView setInputDelegate:self];
		[self addSubview:[_keyboardView inputView]];
		[self addSubview: _keyboardView];
		//[_keyboardView showKeyboard];
	}

	glBindRenderbuffer(GL_RENDERBUFFER, _viewRenderbuffer); printOpenGLError();

	[self clearColorBuffer];

	GLfloat adjustedWidth = _videoContext.screenWidth;
	GLfloat adjustedHeight = _videoContext.screenHeight;
	if (_videoContext.asprectRatioCorrection) {
		if (_videoContext.screenWidth == 320 && _videoContext.screenHeight == 200)
			adjustedHeight = 240;
		else if (_videoContext.screenWidth == 640 && _videoContext.screenHeight == 400)
			adjustedHeight = 480;
	}

	float overlayPortraitRatio;

	if (isLandscape) {
		GLfloat gameScreenRatio = adjustedWidth / adjustedHeight;
		GLfloat screenRatio = (GLfloat)screenWidth / (GLfloat)screenHeight;

		// These are the width/height according to the portrait layout!
		int rectWidth, rectHeight;
		int xOffset, yOffset;

		if (gameScreenRatio < screenRatio) {
			// When the game screen ratio is less than the screen ratio
			// we need to scale the width, since the game screen was higher
			// compared to the width than our output screen is.
			rectWidth = (int)(screenHeight * gameScreenRatio);
			rectHeight = screenHeight;
			xOffset = (screenWidth - rectWidth) / 2;
			yOffset = 0;
		} else {
			// When the game screen ratio is bigger than the screen ratio
			// we need to scale the height, since the game screen was wider
			// compared to the height than our output screen is.
			rectWidth = screenWidth;
			rectHeight = (int)(screenWidth / gameScreenRatio);
			xOffset = 0;
			yOffset = (screenHeight - rectHeight) / 2;
		}

		//printf("Rect: %i, %i, %i, %i\n", xOffset, yOffset, rectWidth, rectHeight);
		_gameScreenRect = CGRectMake(xOffset, yOffset, rectWidth, rectHeight);
		overlayPortraitRatio = 1.0f;
	} else {
		GLfloat ratio = adjustedHeight / adjustedWidth;
		int height = (int)(screenWidth * ratio);
		//printf("Making rect (%u, %u)\n", screenWidth, height);
		_gameScreenRect = CGRectMake(0, 0, screenWidth, height);

		overlayPortraitRatio = (_videoContext.overlayHeight * ratio) / _videoContext.overlayWidth;
	}
	_overlayRect = CGRectMake(0, 0, screenWidth, screenHeight * overlayPortraitRatio);

	_gameScreenCoords[0].x = _gameScreenCoords[2].x = CGRectGetMinX(_gameScreenRect);
	_gameScreenCoords[0].y = _gameScreenCoords[1].y = CGRectGetMinY(_gameScreenRect);
	_gameScreenCoords[1].x = _gameScreenCoords[3].x = CGRectGetMaxX(_gameScreenRect);
	_gameScreenCoords[2].y = _gameScreenCoords[3].y = CGRectGetMaxY(_gameScreenRect);

	_overlayCoords[1].x = _overlayCoords[3].x = CGRectGetMaxX(_overlayRect);
	_overlayCoords[2].y = _overlayCoords[3].y = CGRectGetMaxY(_overlayRect);

	[self setViewTransformation];
	[self updateMouseCursorScaling];
}

- (void)setViewTransformation {
	// Scale the shake offset according to the overlay size. We need this to
	// adjust the overlay mouse click coordinates when an offset is set.
	_scaledShakeOffsetY = (int)(_videoContext.shakeOffsetY / (GLfloat)_videoContext.screenHeight * CGRectGetHeight(_overlayRect));

	glUniform1f(_shakeSlot, _scaledShakeOffsetY);
}

- (void)clearColorBuffer {
	// The color buffer is triple-buffered, so we clear it multiple times right away to avid doing any glClears later.
	int clearCount = 5;
	while (clearCount-- > 0) {
		glClear(GL_COLOR_BUFFER_BIT); printOpenGLError();
		[_context presentRenderbuffer:GL_RENDERBUFFER];
		glFinish();
	}
}

- (void)addEvent:(InternalEvent)event {
	[_eventLock lock];
	_events.push_back(event);
	[_eventLock unlock];
}

- (bool)fetchEvent:(InternalEvent *)event {
	[_eventLock lock];
	if (_events.empty()) {
		[_eventLock unlock];
		return false;
	}

	*event = *_events.begin();
	_events.pop_front();
	[_eventLock unlock];
	return true;
}

- (bool)getMouseCoords:(CGPoint)point eventX:(int *)x eventY:(int *)y {
	// We scale the input according to our scale factor to get actual screen
	// coordinates.
	point.x *= self.contentScaleFactor;
	point.y *= self.contentScaleFactor;

	CGRect *area;
	int width, height, offsetY;
	if (_videoContext.overlayVisible) {
		area = &_overlayRect;
		width = _videoContext.overlayWidth;
		height = _videoContext.overlayHeight;
		offsetY = _scaledShakeOffsetY;
	} else {
		area = &_gameScreenRect;
		width = _videoContext.screenWidth;
		height = _videoContext.screenHeight;
		offsetY = _videoContext.shakeOffsetY;
	}

	point.x = (point.x - CGRectGetMinX(*area)) / CGRectGetWidth(*area);
	point.y = (point.y - CGRectGetMinY(*area)) / CGRectGetHeight(*area);

	*x = (int)(point.x * width);
	// offsetY describes the translation of the screen in the upward direction,
	// thus we need to add it here.
	*y = (int)(point.y * height + offsetY);

	if (!iOS7_touchpadModeEnabled()) {
		// Clip coordinates
		if (*x < 0 || *x > width || *y < 0 || *y > height)
			return false;
	}

	return true;
}

- (void)deviceOrientationChanged:(UIDeviceOrientation)orientation {
	[self addEvent:InternalEvent(kInputOrientationChanged, orientation, 0)];
    
    BOOL isLandscape = (self.bounds.size.width > self.bounds.size.height);
    if (isLandscape) {
        [_keyboardView hideKeyboard];
    } else {
        [_keyboardView showKeyboard];
    }
}
/*
- (UITouch *)secondTouchOtherTouchThan:(UITouch *)touch in:(NSSet *)set {
	NSArray *all = [set allObjects];
	for (UITouch *t in all) {
		if (t != touch) {
			return t;
		}
	}
	return nil;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	int x, y;

	NSSet *allTouches = [event allTouches];
	if (allTouches.count == 1) {
		_firstTouch = [allTouches anyObject];
		CGPoint point = [_firstTouch locationInView:self];
		if (![self getMouseCoords:point eventX:&x eventY:&y])
			return;

		[self addEvent:InternalEvent(kInputMouseDown, x, y)];
	}
	else if (allTouches.count == 2) {
		_secondTouch = [self secondTouchOtherTouchThan:_firstTouch in:allTouches];
		if (_secondTouch) {
			CGPoint point = [_secondTouch locationInView:self];
			if (![self getMouseCoords:point eventX:&x eventY:&y])
				return;

			[self addEvent:InternalEvent(kInputMouseSecondDown, x, y)];
		}
	}
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	int x, y;

	NSSet *allTouches = [event allTouches];
	for (UITouch *touch in allTouches) {
		if (touch == _firstTouch) {
			CGPoint point = [touch locationInView:self];
			if (![self getMouseCoords:point eventX:&x eventY:&y])
				return;

			[self addEvent:InternalEvent(kInputMouseDragged, x, y)];
		} else if (touch == _secondTouch) {
			CGPoint point = [touch locationInView:self];
			if (![self getMouseCoords:point eventX:&x eventY:&y])
				return;

			[self addEvent:InternalEvent(kInputMouseSecondDragged, x, y)];
		}
	}
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	int x, y;

	NSSet *allTouches = [event allTouches];
	if (allTouches.count == 1) {
		UITouch *touch = [allTouches anyObject];
		CGPoint point = [touch locationInView:self];
		if (![self getMouseCoords:point eventX:&x eventY:&y]) {
			return;
		}

		[self addEvent:InternalEvent(kInputMouseUp, x, y)];
	}
	else if (allTouches.count == 2) {
		UITouch *touch = [[allTouches allObjects] objectAtIndex:1];
		CGPoint point = [touch locationInView:self];
		if (![self getMouseCoords:point eventX:&x eventY:&y])
			return;

		[self addEvent:InternalEvent(kInputMouseSecondUp, x, y)];
	}
	_firstTouch = nil;
	_secondTouch = nil;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	_firstTouch = nil;
	_secondTouch = nil;
}
*/
- (void)pan:(UIPanGestureRecognizer *)recognizer {
    int x, y;
    
    CGPoint point = [recognizer locationInView:self];
    if (![self getMouseCoords:point eventX:&x eventY:&y])
        return;
    
    if (recognizer.state == UIGestureRecognizerStateBegan)
        [self addEvent:InternalEvent(kInputMouseDown, x, y)];
    else if (recognizer.state == UIGestureRecognizerStateChanged)
        [self addEvent:InternalEvent(kInputMouseDragged, x, y)];
    else if (recognizer.state == UIGestureRecognizerStateEnded)
        return;
}
    
- (void)swipeRight:(UISwipeGestureRecognizer *)recognizer {
    [self addEvent:InternalEvent(kInputSwipe, kUIViewSwipeRight, recognizer.numberOfTouches)];
}
    
- (void)swipeLeft:(UISwipeGestureRecognizer *)recognizer {
    [self addEvent:InternalEvent(kInputSwipe, kUIViewSwipeLeft, recognizer.numberOfTouches)];
}
    
- (void)swipeUp:(UISwipeGestureRecognizer *)recognizer {
    [self addEvent:InternalEvent(kInputSwipe, kUIViewSwipeUp, recognizer.numberOfTouches)];
    if (recognizer.numberOfTouches == 2)
        [_keyboardView showKeyboard];
}
    
- (void)swipeDown:(UISwipeGestureRecognizer *)recognizer {
    [self addEvent:InternalEvent(kInputSwipe, kUIViewSwipeDown, recognizer.numberOfTouches)];
}
    
- (void)doubleTap:(UITapGestureRecognizer *)recognizer {
    [self addEvent:InternalEvent(kInputTap, kUIViewTapDouble, recognizer.numberOfTouches)];
}
    
- (void)singleTap:(UITapGestureRecognizer *)recognizer {
    int x, y;
    
    CGPoint point = [recognizer locationInView:self];
    if (![self getMouseCoords:point eventX:&x eventY:&y])
        return;
    
    [self addEvent:InternalEvent(kInputMouseDown, x, y)];
    [self addEvent:InternalEvent(kInputTap, kUIViewTapSingle, recognizer.numberOfTouches)];
}
    
- (void)singlePress:(UILongPressGestureRecognizer *)recognizer {
    int x, y;
    CGPoint point = [recognizer locationInView:self];
    if (![self getMouseCoords:point eventX:&x eventY:&y])
        return;
    
    if (recognizer.state == UIGestureRecognizerStateBegan)
    {
        [self addEvent:InternalEvent(kInputMouseDown, x, y)];
        [self addEvent:InternalEvent(kInputLongPress, kUIViewLongPressStarted, 1)];
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged)
        [self addEvent:InternalEvent(kInputMouseDragged, x, y)];
    else if (recognizer.state == UIGestureRecognizerStateEnded)
        [self addEvent:InternalEvent(kInputLongPress, kUIViewLongPressReleased, 1)];
}
    
- (void)doublePress:(UILongPressGestureRecognizer *)recognizer {
    int x, y;
    CGPoint point = [recognizer locationInView:self];
    if (![self getMouseCoords:point eventX:&x eventY:&y])
        return;
    
    if (recognizer.state == UIGestureRecognizerStateBegan)
    {
        [self addEvent:InternalEvent(kInputMouseDown, x, y)];
        [self addEvent:InternalEvent(kInputLongPress, kUIViewLongPressStarted, 2)];
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged)
        [self addEvent:InternalEvent(kInputMouseDragged, x, y)];
    else if (recognizer.state == UIGestureRecognizerStateEnded)
        [self addEvent:InternalEvent(kInputLongPress, kUIViewLongPressReleased, 2)];
}


- (void)handleKeyPress:(unichar)c {
	if (c == '`') {
		[self addEvent:InternalEvent(kInputKeyPressed, '\E', 0)];
	} else {
		[self addEvent:InternalEvent(kInputKeyPressed, c, 0)];
	}
}

- (void)applicationSuspend {
	[self addEvent:InternalEvent(kInputApplicationSuspended, 0, 0)];
}

- (void)applicationResume {
	[self addEvent:InternalEvent(kInputApplicationResumed, 0, 0)];
}

@end
