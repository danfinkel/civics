"""
civic_prism_charts.py
=====================
Matplotlib helpers that produce Civic Prism-branded chart PNGs
ready for direct insertion into PowerPoint via pptxgenjs or python-pptx.

Usage
-----
    from civic_prism_charts import CivicPrismChart

    # context-manager: all charts inside use the brand style
    with CivicPrismChart() as cp:
        fig, ax = cp.line(
            series={"Cohort Alpha": alpha_vals, "Cohort Beta": beta_vals},
            x_labels=months,
            title="Monthly Performance",
            subtitle="Jan–Dec 2024  ·  three cohorts",
        )
        cp.save(fig, "trend.png")

    # one-shot helpers (no context manager needed)
    fig, ax = CivicPrismChart.kpi_sparkline([55,62,70,78,84], color="#1A3A5C")
    CivicPrismChart.save(fig, "spark.png", transparent=True)
"""

from __future__ import annotations

import contextlib
import io
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple, Union

import matplotlib as mpl
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np

# ── Palette ───────────────────────────────────────────────────────────────────

class CP:
    """Civic Prism brand tokens."""
    NAVY       = "#1A3A5C"
    DEEP_NAVY  = "#002444"
    AMBER      = "#FFB800"
    SLATE      = "#64748B"
    OFF_WHITE  = "#FAF9FC"
    TEAL       = "#2D4F52"
    BORDER     = "#E2E8F0"
    WHITE      = "#FFFFFF"
    CYAN       = "#06B6D4"
    GREEN      = "#22C55E"
    PURPLE     = "#7C3AED"
    RED        = "#EF4444"

    # Default series cycle: navy, cyan, amber, green, purple, teal, slate
    CYCLE = [NAVY, CYAN, AMBER, GREEN, PURPLE, TEAL, SLATE]

    # Dark-slide overrides
    DARK_BG    = DEEP_NAVY
    DARK_TEXT  = OFF_WHITE
    DARK_MUTED = "#94A3B8"
    DARK_GRID  = "#1E3A5C"


# ── rcParams dict ─────────────────────────────────────────────────────────────

def _build_rcparams(dark: bool = False) -> dict:
    bg   = CP.DARK_BG    if dark else CP.OFF_WHITE
    axbg = CP.DARK_BG    if dark else CP.WHITE
    txt  = CP.DARK_TEXT  if dark else CP.NAVY
    muted= CP.DARK_MUTED if dark else CP.SLATE
    grid = CP.DARK_GRID  if dark else CP.BORDER
    spine= CP.DARK_GRID  if dark else CP.BORDER

    return {
        # Canvas
        "figure.facecolor":       bg,
        "axes.facecolor":         axbg,
        "figure.dpi":             150,
        "savefig.dpi":            150,
        "savefig.bbox":           "tight",
        "savefig.pad_inches":     0.15,
        "savefig.facecolor":      bg,

        # Spines
        "axes.spines.top":        False,
        "axes.spines.right":      False,
        "axes.spines.left":       True,
        "axes.spines.bottom":     True,
        "axes.edgecolor":         spine,
        "axes.linewidth":         0.75,

        # Grid
        "axes.grid":              True,
        "axes.grid.axis":         "y",
        "grid.color":             grid,
        "grid.linewidth":         0.6,
        "grid.linestyle":         "-",
        "grid.alpha":             1.0,

        # Ticks
        "xtick.color":            muted,
        "ytick.color":            muted,
        "xtick.labelsize":        9,
        "ytick.labelsize":        9,
        "xtick.major.size":       0,
        "ytick.major.size":       0,
        "xtick.major.pad":        6,
        "ytick.major.pad":        6,

        # Labels
        "axes.labelcolor":        muted,
        "axes.labelsize":         10,
        "axes.labelpad":          8,
        "axes.titlesize":         13,
        "axes.titleweight":       "bold",
        "axes.titlecolor":        txt,
        "axes.titlepad":          12,

        # Lines
        "lines.linewidth":        2.2,
        "lines.solid_capstyle":   "round",
        "patch.linewidth":        0,

        # Legend
        "legend.frameon":         False,
        "legend.fontsize":        9,
        "legend.labelcolor":      txt,

        # Color cycle
        "axes.prop_cycle": plt.cycler("color", CP.CYCLE),
    }


LIGHT_STYLE = _build_rcparams(dark=False)
DARK_STYLE  = _build_rcparams(dark=True)


# ── Main class ────────────────────────────────────────────────────────────────

class CivicPrismChart:
    """
    Factory and context-manager for Civic Prism charts.

    Parameters
    ----------
    dark : bool
        Use the deep-navy dark background style (for section slides).
    figsize : tuple
        Default figure size in inches. Can be overridden per chart.

    Examples
    --------
    >>> cp = CivicPrismChart()
    >>> with cp:
    ...     fig, ax = cp.line({"Alpha": [1,2,3]}, x_labels=["a","b","c"])
    ...     cp.save(fig, "out.png")

    >>> # or as a plain factory (no context manager)
    >>> fig, ax = CivicPrismChart().bar({"NPS": [72,65,80]}, x_labels=["Q1","Q2","Q3"])
    """

    def __init__(self, dark: bool = False, figsize: Tuple[float, float] = (7, 3.5)):
        self.dark = dark
        self.figsize = figsize
        self._rc = DARK_STYLE if dark else LIGHT_STYLE
        self._ctx: Optional[contextlib.ExitStack] = None

    # ── context manager ───────────────────────────────────────────────────────

    def __enter__(self) -> "CivicPrismChart":
        self._ctx = contextlib.ExitStack()
        self._ctx.enter_context(mpl.rc_context(self._rc))
        return self

    def __exit__(self, *args):
        if self._ctx:
            self._ctx.close()
            self._ctx = None

    def _apply(self):
        """Apply rcParams inline (when not using context manager)."""
        mpl.rcParams.update(self._rc)

    # ── shared internal helpers ───────────────────────────────────────────────

    def _fig_ax(self, figsize=None) -> Tuple[plt.Figure, plt.Axes]:
        with mpl.rc_context(self._rc):
            return plt.subplots(figsize=figsize or self.figsize)

    @staticmethod
    def _add_title(ax: plt.Axes, title: Optional[str], subtitle: Optional[str]):
        if title:
            ax.set_title(title, loc="left", pad=14)
        if subtitle:
            ax.text(0.0, 1.03, subtitle, transform=ax.transAxes,
                    fontsize=9, color=CP.SLATE, va="bottom")

    @staticmethod
    def _amber_accent(ax: plt.Axes, value: float,
                      label: str = "Target", axis: str = "y"):
        """Draw a dashed amber reference line on x or y axis."""
        if axis == "y":
            ax.axhline(value, color=CP.AMBER, linewidth=1.2,
                       linestyle="--", alpha=0.8, zorder=2)
            xlim = ax.get_xlim()
            ax.text(xlim[1], value, f" {label}", va="center",
                    fontsize=8, color=CP.AMBER)
        else:
            ax.axvline(value, color=CP.AMBER, linewidth=1.2,
                       linestyle="--", alpha=0.8, zorder=2)

    # ── chart methods ─────────────────────────────────────────────────────────

    def line(
        self,
        series: Dict[str, Sequence[float]],
        x_labels: Optional[Sequence] = None,
        *,
        title: Optional[str] = None,
        subtitle: Optional[str] = None,
        fill: bool = True,
        terminal_dot: bool = True,
        y_label: Optional[str] = None,
        y_fmt: str = "{:.0f}",
        reference: Optional[Tuple[float, str]] = None,
        figsize: Optional[Tuple[float, float]] = None,
    ) -> Tuple[plt.Figure, plt.Axes]:
        """
        Multi-series line chart with optional area fill.

        Parameters
        ----------
        series : dict of {label: values}
        x_labels : tick labels for the x-axis
        fill : shade area under each line (alpha 0.07)
        terminal_dot : place a filled circle at the last data point
        reference : (value, label) for an amber dashed reference line
        """
        with mpl.rc_context(self._rc):
            fig, ax = plt.subplots(figsize=figsize or self.figsize)
            colors = iter(CP.CYCLE)

            for label, vals in series.items():
                color = next(colors)
                xs = range(len(vals))
                line, = ax.plot(xs, vals, label=label, color=color,
                                linewidth=2.2, solid_capstyle="round")
                if fill:
                    ax.fill_between(xs, vals, min(vals),
                                    alpha=0.07, color=color)
                if terminal_dot:
                    ax.plot(xs[-1], vals[-1], "o",
                            color=color, ms=5, zorder=5)

            if x_labels is not None:
                ax.set_xticks(range(len(x_labels)))
                ax.set_xticklabels(x_labels)

            if y_label:
                ax.set_ylabel(y_label)

            if y_fmt:
                ax.yaxis.set_major_formatter(
                    mticker.FuncFormatter(lambda v, _: y_fmt.format(v)))

            if reference:
                self._amber_accent(ax, reference[0], reference[1])

            ax.legend(loc="upper left", ncols=len(series))
            self._add_title(ax, title, subtitle)
            fig.tight_layout()
            return fig, ax

    def bar(
        self,
        series: Dict[str, Sequence[float]],
        x_labels: Optional[Sequence] = None,
        *,
        title: Optional[str] = None,
        subtitle: Optional[str] = None,
        horizontal: bool = False,
        show_values: bool = True,
        value_fmt: str = "{:.0f}",
        reference: Optional[Tuple[float, str]] = None,
        figsize: Optional[Tuple[float, float]] = None,
    ) -> Tuple[plt.Figure, plt.Axes]:
        """
        Grouped or single-series bar chart (vertical or horizontal).

        Parameters
        ----------
        show_values : annotate bar ends with their value
        horizontal : flip to a horizontal bar chart
        """
        with mpl.rc_context(self._rc):
            fig, ax = plt.subplots(figsize=figsize or self.figsize)
            n_series = len(series)
            n_groups = max(len(v) for v in series.values())
            width = 0.75 / n_series
            colors = iter(CP.CYCLE)

            for i, (label, vals) in enumerate(series.items()):
                color = next(colors)
                offsets = np.arange(len(vals)) + i * width - (n_series - 1) * width / 2

                if horizontal:
                    bars = ax.barh(offsets, vals, height=width * 0.85,
                                   color=color, label=label)
                    if show_values:
                        for bar in bars:
                            w = bar.get_width()
                            ax.text(w + 0.5, bar.get_y() + bar.get_height() / 2,
                                    value_fmt.format(w), va="center",
                                    fontsize=8, color=CP.NAVY)
                else:
                    bars = ax.bar(offsets, vals, width=width * 0.85,
                                  color=color, label=label)
                    if show_values:
                        for bar in bars:
                            h = bar.get_height()
                            ax.text(bar.get_x() + bar.get_width() / 2,
                                    h + ax.get_ylim()[1] * 0.01,
                                    value_fmt.format(h), ha="center",
                                    fontsize=8, color=CP.NAVY)

            if x_labels is not None and not horizontal:
                ax.set_xticks(np.arange(n_groups))
                ax.set_xticklabels(x_labels)
            elif x_labels is not None and horizontal:
                ax.set_yticks(np.arange(n_groups))
                ax.set_yticklabels(x_labels)

            if reference:
                self._amber_accent(ax, reference[0], reference[1],
                                   axis="x" if horizontal else "y")

            if n_series > 1:
                ax.legend(loc="upper right")
            self._add_title(ax, title, subtitle)
            fig.tight_layout()
            return fig, ax

    def scatter(
        self,
        x: Sequence[float],
        y: Sequence[float],
        *,
        color_values: Optional[Sequence[float]] = None,
        size_values: Optional[Sequence[float]] = None,
        title: Optional[str] = None,
        subtitle: Optional[str] = None,
        x_label: Optional[str] = None,
        y_label: Optional[str] = None,
        trend_line: bool = True,
        stat_annotation: bool = True,
        figsize: Optional[Tuple[float, float]] = None,
    ) -> Tuple[plt.Figure, plt.Axes]:
        """
        Scatter plot with optional OLS trend line and r/p annotation.

        Parameters
        ----------
        color_values : numeric array → mapped to navy gradient colormap
        size_values  : numeric array → mapped to dot size (20–120)
        trend_line   : draw amber dashed OLS fit
        stat_annotation : show r, p, n in top-left corner
        """
        with mpl.rc_context(self._rc):
            fig, ax = plt.subplots(figsize=figsize or self.figsize)

            cmap = mpl.colors.LinearSegmentedColormap.from_list(
                "cp_scatter", [CP.BORDER, CP.NAVY])

            sizes = None
            if size_values is not None:
                sv = np.asarray(size_values, dtype=float)
                sizes = 20 + 100 * (sv - sv.min()) / (sv.ptp() or 1)

            ax.scatter(
                x, y,
                c=color_values if color_values is not None else CP.NAVY,
                cmap=cmap if color_values is not None else None,
                s=sizes if sizes is not None else 55,
                alpha=0.75, linewidths=0, zorder=3,
            )

            if trend_line:
                m, b = np.polyfit(x, y, 1)
                xs = np.linspace(min(x), max(x), 200)
                ax.plot(xs, m * xs + b, color=CP.AMBER,
                        lw=1.5, linestyle="--", alpha=0.85)

            if stat_annotation:
                r = float(np.corrcoef(x, y)[0, 1])
                # simple two-tailed p approximation via t-stat
                n = len(x)
                from scipy import stats as _stats
                _, p = _stats.pearsonr(x, y)
                p_str = "< 0.001" if p < 0.001 else f"= {p:.3f}"
                ax.text(0.04, 0.96,
                        f"r = {r:.2f}  ·  p {p_str}  ·  n = {n}",
                        transform=ax.transAxes, va="top",
                        fontsize=8.5, color=CP.SLATE)

            if x_label:
                ax.set_xlabel(x_label)
            if y_label:
                ax.set_ylabel(y_label)

            self._add_title(ax, title, subtitle)
            fig.tight_layout()
            return fig, ax

    def heatmap(
        self,
        data: Union[np.ndarray, "pd.DataFrame"],
        row_labels: Optional[Sequence[str]] = None,
        col_labels: Optional[Sequence[str]] = None,
        *,
        title: Optional[str] = None,
        subtitle: Optional[str] = None,
        fmt: str = ".0f",
        cbar: bool = False,
        figsize: Optional[Tuple[float, float]] = None,
    ) -> Tuple[plt.Figure, plt.Axes]:
        """
        Heatmap / correlation matrix using the off-white → navy gradient.

        Works with a raw numpy array or a pandas DataFrame.
        Requires seaborn (optional dep); falls back to imshow otherwise.
        """
        with mpl.rc_context(self._rc):
            fig, ax = plt.subplots(figsize=figsize or (5.5, 4.5))
            cmap = mpl.colors.LinearSegmentedColormap.from_list(
                "cp_heat", [CP.OFF_WHITE, CP.NAVY])

            try:
                import seaborn as sns
                sns.heatmap(
                    data, ax=ax, cmap=cmap,
                    annot=True, fmt=fmt,
                    annot_kws={"size": 9, "color": CP.NAVY},
                    linewidths=0.4, linecolor=CP.BORDER,
                    cbar=cbar, square=True,
                    xticklabels=col_labels if col_labels is not None else "auto",
                    yticklabels=row_labels if row_labels is not None else "auto",
                )
                ax.tick_params(length=0)
                plt.setp(ax.get_xticklabels(), rotation=0, ha="center")
                plt.setp(ax.get_yticklabels(), rotation=0)
            except ImportError:
                # fallback: plain imshow
                arr = np.asarray(data, dtype=float)
                im = ax.imshow(arr, cmap=cmap, aspect="auto")
                if row_labels:
                    ax.set_yticks(range(len(row_labels)))
                    ax.set_yticklabels(row_labels)
                if col_labels:
                    ax.set_xticks(range(len(col_labels)))
                    ax.set_xticklabels(col_labels)
                for (r, c), val in np.ndenumerate(arr):
                    ax.text(c, r, f"{val:{fmt}}", ha="center",
                            va="center", fontsize=9, color=CP.NAVY)

            self._add_title(ax, title, subtitle)
            fig.tight_layout()
            return fig, ax

    def distribution(
        self,
        data: Dict[str, Sequence[float]],
        *,
        title: Optional[str] = None,
        subtitle: Optional[str] = None,
        bins: int = 30,
        kde: bool = True,
        figsize: Optional[Tuple[float, float]] = None,
    ) -> Tuple[plt.Figure, plt.Axes]:
        """
        Overlapping distributions (histogram + optional KDE).

        Parameters
        ----------
        data : dict of {label: values}
        kde  : overlay a kernel density estimate curve
        """
        with mpl.rc_context(self._rc):
            fig, ax = plt.subplots(figsize=figsize or (5, 3.5))
            colors = iter(CP.CYCLE)

            for label, vals in data.items():
                color = next(colors)
                ax.hist(vals, bins=bins, alpha=0.25, color=color,
                        label=label, density=True)
                if kde:
                    try:
                        from scipy.stats import gaussian_kde
                        xs = np.linspace(min(vals), max(vals), 300)
                        kde_vals = gaussian_kde(vals)(xs)
                        ax.plot(xs, kde_vals, color=color, linewidth=2.0)
                    except ImportError:
                        pass  # skip KDE if scipy not available

            ax.set_ylabel("Density")
            ax.yaxis.set_major_formatter(mticker.FormatStrFormatter("%.2f"))
            ax.legend()
            self._add_title(ax, title, subtitle)
            fig.tight_layout()
            return fig, ax

    def kpi_sparkline(
        self,
        values: Sequence[float],
        color: str = CP.NAVY,
        *,
        figsize: Tuple[float, float] = (2.8, 0.55),
        transparent: bool = True,
    ) -> Tuple[plt.Figure, plt.Axes]:
        """
        Tiny axis-free sparkline for KPI cards.

        Returns a transparent PNG-ready figure. Call save(..., transparent=True).
        """
        with mpl.rc_context(self._rc):
            fig, ax = plt.subplots(figsize=figsize)
            if transparent:
                fig.patch.set_alpha(0)
                ax.patch.set_alpha(0)

            xs = range(len(values))
            ax.plot(values, color=color, linewidth=2.0,
                    solid_capstyle="round", zorder=3)
            ax.fill_between(xs, values, min(values),
                            alpha=0.12, color=color)
            ax.plot(xs[-1], values[-1], "o",
                    color=color, ms=4, zorder=5)
            ax.axis("off")
            for spine in ax.spines.values():
                spine.set_visible(False)

            fig.tight_layout(pad=0)
            return fig, ax

    def annotate(
        self,
        ax: plt.Axes,
        xy: Tuple[float, float],
        text: str,
        *,
        offset: Tuple[float, float] = (8, 8),
        color: str = CP.NAVY,
        arrow_color: str = CP.AMBER,
    ) -> None:
        """
        Add an amber-arrowed callout annotation to any axes.

        Parameters
        ----------
        xy     : data coordinates of the point to annotate
        text   : annotation text
        offset : (dx, dy) offset in points for the text box
        """
        ax.annotate(
            text,
            xy=xy,
            xytext=offset,
            textcoords="offset points",
            fontsize=9, color=color,
            arrowprops=dict(
                arrowstyle="-|>",
                color=arrow_color,
                lw=1.4,
                shrinkA=0, shrinkB=4,
            ),
        )

    def multi_panel(
        self,
        layout: Tuple[int, int],
        *,
        figsize: Optional[Tuple[float, float]] = None,
        sharex: bool = False,
        sharey: bool = False,
    ) -> Tuple[plt.Figure, np.ndarray]:
        """
        Create a branded multi-panel figure (e.g. 1×3 or 2×2 dashboard).

        Returns (fig, axes_array) — axes_array is always 2-D.
        """
        rows, cols = layout
        fs = figsize or (cols * 3.8, rows * 3.2)
        with mpl.rc_context(self._rc):
            fig, axes = plt.subplots(
                rows, cols, figsize=fs,
                sharex=sharex, sharey=sharey,
                squeeze=False,
            )
            fig.subplots_adjust(hspace=0.45, wspace=0.35)
            return fig, axes

    # ── static save helper ────────────────────────────────────────────────────

    @staticmethod
    def save(
        fig: plt.Figure,
        path: Union[str, Path, io.BytesIO],
        *,
        dpi: int = 150,
        transparent: bool = False,
        close: bool = True,
    ) -> Path | io.BytesIO:
        """
        Save a figure to disk or a BytesIO buffer.

        Parameters
        ----------
        path        : file path (str/Path) or io.BytesIO for in-memory use
        dpi         : output resolution (150 is the pptx sweet spot)
        transparent : True for sparklines / overlays on coloured slide backgrounds
        close       : close the figure after saving (recommended)

        Returns
        -------
        The path or buffer passed in, for chaining.
        """
        kwargs = dict(
            dpi=dpi,
            bbox_inches="tight",
            pad_inches=0.15 if not transparent else 0,
            transparent=transparent,
        )
        if isinstance(path, io.BytesIO):
            fig.savefig(path, format="png", **kwargs)
            path.seek(0)
        else:
            path = Path(path)
            path.parent.mkdir(parents=True, exist_ok=True)
            fig.savefig(path, **kwargs)

        if close:
            plt.close(fig)

        return path

    @staticmethod
    def to_base64(fig: plt.Figure, *, dpi: int = 150,
                  transparent: bool = False, close: bool = True) -> str:
        """
        Return the figure as a base64-encoded PNG string — useful for
        embedding directly into pptxgenjs addImage calls.

        Returns
        -------
        str in the form "image/png;base64,<data>"
        """
        import base64
        buf = io.BytesIO()
        CivicPrismChart.save(fig, buf, dpi=dpi,
                             transparent=transparent, close=close)
        return "image/png;base64," + base64.b64encode(buf.read()).decode()

    # ── class-level apply (no context manager) ────────────────────────────────

    @classmethod
    def apply_global(cls, dark: bool = False) -> None:
        """
        Apply Civic Prism rcParams globally for the current session.
        Useful in Jupyter notebooks where you want every chart styled.
        """
        mpl.rcParams.update(DARK_STYLE if dark else LIGHT_STYLE)

    @classmethod
    def style_dict(cls, dark: bool = False) -> dict:
        """Return the raw rcParams dict (e.g. to pass to mpl.rc_context)."""
        return DARK_STYLE.copy() if dark else LIGHT_STYLE.copy()