package net.gree.unitywebview;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.util.TypedValue;
import android.webkit.WebView;

public class RoundedWebView extends WebView{
    private Context context;
    private int width;
    private int height;
    private int radius;
    private int dpRadius;

    public RoundedWebView(Context context, int radius)
    {
        super(context);
        this.dpRadius = radius;
        initialize(context);
    }

    public RoundedWebView(Context context, AttributeSet attrs, int radius)
    {
        super(context, attrs);
        this.dpRadius = radius;
        initialize(context);
    }

    public RoundedWebView(Context context, AttributeSet attrs, int defStyleAttr, int radius)
    {
        super(context, attrs, defStyleAttr);
        this.dpRadius = radius;
        initialize(context);
    }

    private void initialize(Context context)
    {
        this.context = context;
    }

    private float dpToPx(Context context, int dp)
    {
        return TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, context.getResources().getDisplayMetrics());
    }

    @Override protected void onSizeChanged(int newWidth, int newHeight, int oldWidth, int oldHeight)
    {
        super.onSizeChanged(newWidth, newHeight, oldWidth, oldHeight);

        width = newWidth;

        height = newHeight;

        radius = (int)dpToPx(context, this.dpRadius);
    }

    @Override protected void onDraw(Canvas canvas)
    {
        super.onDraw(canvas);

        Path path = new Path();

        path.setFillType(Path.FillType.INVERSE_WINDING);

        path.addRoundRect(new RectF(0, getScrollY(), width, getScrollY() + height), radius, radius, Path.Direction.CW);

        canvas.drawPath(path, createPorterDuffClearPaint());
    }

    private Paint createPorterDuffClearPaint()
    {
        Paint paint = new Paint();

        paint.setColor(Color.TRANSPARENT);

        paint.setStyle(Paint.Style.FILL);

        paint.setAntiAlias(true);

        paint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.CLEAR));

        return paint;
    }
}
